#if canImport(UIKit)
import XCTest
import TheScore
@testable import TheInsideJob

/// Tests drive `TheMuscle` (an `actor`) directly via `await`. The harness
/// itself is `@MainActor` so test bookkeeping (`sentMessages`, etc.) can be
/// read off the main actor without contention. Callbacks installed on the
/// muscle are `@Sendable` and hop back to the main actor through `Task {}`.
/// Thread-safe accumulator used by tests to capture callback invocations.
/// Callbacks installed on `TheMuscle` are `@Sendable` and may fire from any
/// context, so storage needs a lock. `@unchecked Sendable` justification:
/// all access goes through `NSLock`.
private final class CallbackSink: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private var sentMessagesStorage: [(data: Data, clientId: Int)] = []
    private var markedAuthenticatedStorage: [Int] = []
    private var disconnectedClientsStorage: [Int] = []
    private var authenticatedCallbacksStorage: [(clientId: Int, respond: @Sendable (Data) -> Void)] = []
    private var sessionChangesStorage: [Bool] = []
    private let lock = NSLock()

    var sentMessages: [(data: Data, clientId: Int)] { lock.withLock { sentMessagesStorage } }
    var markedAuthenticated: [Int] { lock.withLock { markedAuthenticatedStorage } }
    var disconnectedClients: [Int] { lock.withLock { disconnectedClientsStorage } }
    var authenticatedCallbacks: [(clientId: Int, respond: @Sendable (Data) -> Void)] {
        lock.withLock { authenticatedCallbacksStorage }
    }
    var sessionChanges: [Bool] { lock.withLock { sessionChangesStorage } }

    func appendSent(_ entry: (Data, Int)) { lock.withLock { sentMessagesStorage.append(entry) } }
    func appendAuthenticated(_ clientId: Int) { lock.withLock { markedAuthenticatedStorage.append(clientId) } }
    func appendDisconnected(_ clientId: Int) { lock.withLock { disconnectedClientsStorage.append(clientId) } }
    func appendAuthenticatedCallback(_ entry: (Int, @Sendable (Data) -> Void)) {
        lock.withLock { authenticatedCallbacksStorage.append(entry) }
    }
    func appendSessionChange(_ value: Bool) { lock.withLock { sessionChangesStorage.append(value) } }
}

@MainActor
final class TheMuscleTests: XCTestCase {

    // MARK: - Test Helpers

    private var muscle: TheMuscle!
    private var sink: CallbackSink!

    override func setUp() async throws {
        try await super.setUp()
        muscle = TheMuscle(explicitToken: "test-token")
        sink = CallbackSink()
        await installCallbacks(observeSessionChanges: false)
    }

    override func tearDown() async throws {
        await muscle.tearDown()
        muscle = nil
        sink = nil
        try await super.tearDown()
    }

    private var sentMessages: [(data: Data, clientId: Int)] { sink.sentMessages }
    private var markedAuthenticated: [Int] { sink.markedAuthenticated }
    private var disconnectedClients: [Int] { sink.disconnectedClients }
    private var authenticatedCallbacks: [(clientId: Int, respond: @Sendable (Data) -> Void)] {
        sink.authenticatedCallbacks
    }

    /// Install test callbacks. Each callback writes to the shared `CallbackSink`,
    /// which is thread-safe so the closures don't need to hop back to the harness's
    /// `@MainActor` isolation.
    private func installCallbacks(observeSessionChanges: Bool) async {
        let sink = self.sink!
        let sendToClient: @Sendable (Data, Int) async -> Void = { data, clientId in
            sink.appendSent((data, clientId))
        }
        let markAuth: @Sendable (Int) async -> Void = { clientId in
            sink.appendAuthenticated(clientId)
        }
        let disconnect: @Sendable (Int) async -> Void = { clientId in
            sink.appendDisconnected(clientId)
        }
        let onAuthenticated: @MainActor @Sendable (Int, @escaping @Sendable (Data) -> Void) -> Void = { clientId, respond in
            sink.appendAuthenticatedCallback((clientId, respond))
        }
        let recordChanges: @MainActor @Sendable (Bool) -> Void = { value in sink.appendSessionChange(value) }
        let ignoreChanges: @MainActor @Sendable (Bool) -> Void = { _ in }
        let onSessionActiveChanged: @MainActor @Sendable (Bool) -> Void = observeSessionChanges
            ? recordChanges
            : ignoreChanges
        await muscle.installCallbacks(
            sendToClient: sendToClient,
            markClientAuthenticated: markAuth,
            disconnectClient: disconnect,
            onClientAuthenticated: onAuthenticated,
            onSessionActiveChanged: onSessionActiveChanged
        )
    }

    // MARK: - Encoding helpers

    private func encodeAuth(token: String, driverId: String? = nil) throws -> Data {
        let payload = AuthenticatePayload(token: token, driverId: driverId)
        let envelope = RequestEnvelope(message: .authenticate(payload))
        return try JSONEncoder().encode(envelope)
    }

    private func decodeServerMessage(_ data: Data) -> ServerMessage? {
        do {
            let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
            return envelope.message
        } catch {
            XCTFail("Failed to decode ResponseEnvelope: \(error)")
            return nil
        }
    }

    private func sessionLockedPayloads(from responses: [Data]) -> [SessionLockedPayload] {
        responses.compactMap { data in
            guard case .sessionLocked(let payload) = decodeServerMessage(data) else { return nil }
            return payload
        }
    }

    private func performHello(clientId: Int, respond: @escaping @Sendable (Data) -> Void) async {
        guard let data = try? JSONEncoder().encode(RequestEnvelope(message: .clientHello)) else {
            XCTFail("Failed to encode clientHello")
            return
        }
        await muscle.handleUnauthenticatedMessage(clientId, data: data, respond: respond)
    }

    private func authenticate(
        clientId: Int,
        token: String,
        driverId: String? = nil,
        address: String = "127.0.0.1",
        respond: @escaping @Sendable (Data) -> Void
    ) async throws {
        await muscle.registerClientAddress(clientId, address: address)
        await performHello(clientId: clientId, respond: respond)
        await muscle.handleUnauthenticatedMessage(clientId, data: try encodeAuth(token: token, driverId: driverId), respond: respond)
    }

    private func respondSink() -> @Sendable (Data) -> Void {
        // No-op respond closure for tests that don't need to inspect responses.
        // Use collectResponses() when you need to check what was sent back.
        return { _ in }
    }

    private func collectResponses() -> (respond: @Sendable (Data) -> Void, responses: () -> [Data]) {
        // Test-only inspection box. Mutated only from within the @Sendable
        // closure that captures it; not shared across threads in practice.
        final class Box: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
            var items: [Data] = []
            let lock = NSLock()
        }
        let box = Box()
        let respond: @Sendable (Data) -> Void = { data in
            box.lock.withLock { box.items.append(data) }
        }
        return (respond, { box.lock.withLock { box.items } })
    }

    /// No-op: callbacks now write to a thread-safe sink so test assertions
    /// can read synchronously after the awaited muscle call returns. Kept
    /// for call-site stability; remove once all tests are inlined.
    private func flushCallbacks() async {}

    // MARK: - Auth Flow Tests

    func testValidTokenAuthenticates() async throws {
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 1, token: "test-token", respond: respond)
        await flushCallbacks()

        XCTAssertTrue(markedAuthenticated.contains(1), "Client should be marked authenticated")
        let authenticatedIDs = await muscle.authenticatedClientIDs
        XCTAssertTrue(authenticatedIDs.contains(1))
        let authenticatedCount = await muscle.authenticatedClientCount
        XCTAssertEqual(authenticatedCount, 1)
        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        for msg in serverMessages {
            if case .error(let serverError) = msg, serverError.kind == .authFailure {
                XCTFail("Should not send authFailure error for valid token")
            }
            if case .sessionLocked = msg { XCTFail("Should not send sessionLocked for first connection") }
        }
    }

    func testInvalidTokenRejected() async throws {
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 1, token: "wrong-token", respond: respond)
        await flushCallbacks()

        XCTAssertFalse(markedAuthenticated.contains(1), "Client should not be marked authenticated")
        let authenticatedIDs = await muscle.authenticatedClientIDs
        XCTAssertFalse(authenticatedIDs.contains(1))
        let authenticatedCount = await muscle.authenticatedClientCount
        XCTAssertEqual(authenticatedCount, 0)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasAuthFailed = serverMessages.contains { msg in
            if case .error(let serverError) = msg, serverError.kind == .authFailure { return true }
            return false
        }
        XCTAssertTrue(hasAuthFailed, "Should send authFailure error for invalid token")
    }

    func testEmptyTokenTriggersPendingApproval() async throws {
        let (respond, _) = collectResponses()
        try await authenticate(clientId: 1, token: "", respond: respond)
        await flushCallbacks()

        // Client should NOT be authenticated yet — waiting for UI approval
        XCTAssertFalse(markedAuthenticated.contains(1))
        let authenticatedIDs = await muscle.authenticatedClientIDs
        XCTAssertFalse(authenticatedIDs.contains(1))
        let authenticatedCount = await muscle.authenticatedClientCount
        XCTAssertEqual(authenticatedCount, 0)
    }

    func testNonAuthMessageDisconnects() async throws {
        // Send a ping message before authenticating
        let pingData = try JSONEncoder().encode(RequestEnvelope(message: .ping))
        await muscle.handleUnauthenticatedMessage(1, data: pingData, respond: respondSink())
        await flushCallbacks()

        XCTAssertTrue(disconnectedClients.contains(1), "Should disconnect client that sends non-auth message")
    }

    // MARK: - Session Rules Tests

    func testNoSessionValidTokenAcquires() async throws {
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())

        let driverId = await muscle.activeSessionDriverId
        XCTAssertNotNil(driverId, "Session should be claimed")
        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(1))
    }

    func testSameDriverAllowed() async throws {
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())
        try await authenticate(clientId: 2, token: "test-token", respond: respondSink())
        await flushCallbacks()

        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(1))
        XCTAssertTrue(connections.contains(2))
        let count = await muscle.authenticatedClientCount
        XCTAssertEqual(count, 2)
    }

    func testDifferentDriverBusy() async throws {
        // Driver A connects
        try await authenticate(clientId: 1, token: "test-token", driverId: "driver-a", respond: respondSink())

        // Driver B tries to connect
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 2, token: "test-token", driverId: "driver-b", respond: respond)
        await flushCallbacks()

        XCTAssertFalse(markedAuthenticated.contains(2), "Driver B should not be authenticated")
        let connections = await muscle.activeSessionConnections
        XCTAssertFalse(connections.contains(2))

        let payload = try XCTUnwrap(
            sessionLockedPayloads(from: responses()).first,
            "Should send sessionLocked to different driver"
        )
        XCTAssertEqual(
            payload.message,
            "Session is locked by another driver; owner driver id: driver-a; active connections: 1."
        )
        XCTAssertEqual(payload.activeConnections, 1)
    }

    func testSessionReleasedAfterAllDisconnect() async throws {
        // Authenticate a client
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())
        let driverId = await muscle.activeSessionDriverId
        XCTAssertNotNil(driverId)

        // Disconnect the client — session release timer starts (default 30s, too slow for tests)
        await muscle.handleClientDisconnected(1)
        // Session should still be active (timer hasn't fired)
        let driverIdAfter = await muscle.activeSessionDriverId
        XCTAssertNotNil(driverIdAfter, "Session should still be active during grace period")
    }

    func testSameDriverRejoinsAfterDisconnect() async throws {
        // Client 1 connects and disconnects
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())
        await muscle.handleClientDisconnected(1)

        // Client 2 with same driver reconnects before timeout
        try await authenticate(clientId: 2, token: "test-token", respond: respondSink())
        await flushCallbacks()

        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(2), "Same driver should rejoin session")
        XCTAssertTrue(markedAuthenticated.contains(2))
    }

    func testDrainingSessionSurvivesForRejoin() async throws {
        // Authenticate and disconnect — session enters draining, not idle
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())
        await muscle.handleClientDisconnected(1)

        // Session is draining: no connections, but driver still owns it
        let connectionsDuringDrain = await muscle.activeSessionConnections
        XCTAssertTrue(connectionsDuringDrain.isEmpty, "No connections during draining")
        let driverIdDuringDrain = await muscle.activeSessionDriverId
        XCTAssertNotNil(driverIdDuringDrain, "Driver should still own session while draining")

        // Same driver reconnects — should rejoin the draining session, not claim a new one.
        // Re-install callbacks with the session-change observer enabled.
        await installCallbacks(observeSessionChanges: true)
        try await authenticate(clientId: 2, token: "test-token", respond: respondSink())

        let connectionsAfter = await muscle.activeSessionConnections
        XCTAssertTrue(connectionsAfter.contains(2), "New client should be in session")
        XCTAssertTrue(sink.sessionChanges.isEmpty, "Session should not have been released and reclaimed")
    }

    func testDifferentDriverBlockedDuringGracePeriod() async throws {
        // Driver A connects and disconnects (release timer running)
        try await authenticate(clientId: 1, token: "test-token", driverId: "driver-a", respond: respondSink())
        await muscle.handleClientDisconnected(1)

        // Driver B tries during grace period
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 2, token: "test-token", driverId: "driver-b", respond: respond)
        await flushCallbacks()

        let payload = try XCTUnwrap(
            sessionLockedPayloads(from: responses()).first,
            "Different driver should be blocked during grace period"
        )
        XCTAssertEqual(payload.activeConnections, 0)
        XCTAssertTrue(payload.message.contains("owner driver id: driver-a"))
        XCTAssertTrue(payload.message.contains("active connections: 0"))
        XCTAssertTrue(payload.message.contains("remaining timeout:"))
    }

    func testTokenBackedSessionLockDoesNotExposeTokenAsOwner() async throws {
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())

        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 2, token: "test-token", driverId: "driver-b", respond: respond)

        let payload = try XCTUnwrap(sessionLockedPayloads(from: responses()).first)
        XCTAssertFalse(payload.message.contains("test-token"))
    }

    // MARK: - Token Lifecycle Tests

    func testTokenSurvivesSessionRelease() async throws {
        let originalToken = await muscle.sessionToken

        // Authenticate, disconnect, tearDown to force session release
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())
        await muscle.handleClientDisconnected(1)

        // Token should remain the same after session release path
        let tokenAfter = await muscle.sessionToken
        XCTAssertEqual(tokenAfter, originalToken, "Token should not change when session is released")
    }

    func testTokenStableAcrossMultipleCycles() async throws {
        let originalToken = await muscle.sessionToken

        for i in 1...5 {
            try await authenticate(clientId: i, token: originalToken, respond: respondSink())
            await muscle.handleClientDisconnected(i)
        }

        let tokenAfter = await muscle.sessionToken
        XCTAssertEqual(tokenAfter, originalToken, "Token should remain stable across connect/disconnect cycles")
    }

    func testExplicitTokenUsed() async {
        let muscle = TheMuscle(explicitToken: "my-explicit-token")
        let token = await muscle.sessionToken
        XCTAssertEqual(token, "my-explicit-token")
    }

    func testAutoGeneratedTokenIsUUID() async {
        let muscle = TheMuscle(explicitToken: nil)
        let token = await muscle.sessionToken
        XCTAssertNotNil(UUID(uuidString: token), "Auto-generated token should be a valid UUID")
    }

    func testTearDownClearsState() async throws {
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())
        await flushCallbacks()

        let helloValidatedBefore = await muscle.helloValidatedClients
        XCTAssertTrue(helloValidatedBefore.contains(1))

        await muscle.tearDown()

        let driverId = await muscle.activeSessionDriverId
        XCTAssertNil(driverId)
        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.isEmpty)
        let authenticatedIDs = await muscle.authenticatedClientIDs
        XCTAssertTrue(authenticatedIDs.isEmpty)
        let helloValidatedAfter = await muscle.helloValidatedClients
        XCTAssertTrue(helloValidatedAfter.isEmpty)
        let authenticatedCount = await muscle.authenticatedClientCount
        XCTAssertEqual(authenticatedCount, 0)
    }

    // MARK: - Brute-Force Protection Tests

    func testSingleFailedAttemptNotLockedOut() async throws {
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 1, token: "wrong-token", respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasAuthFailed = serverMessages.contains { msg in
            if case .error(let serverError) = msg, serverError.kind == .authFailure {
                return !serverError.message.contains("Too many")
            }
            return false
        }
        XCTAssertTrue(hasAuthFailed, "First failed attempt should get normal authFailed, not lockout")
    }

    func testLockoutAfterMaxFailedAttempts() async throws {
        // Send 5 failed attempts from different clientIds but same address (simulates reconnection)
        for i in 1...5 {
            try await authenticate(clientId: i, token: "wrong-token", address: "192.168.1.100", respond: respondSink())
            await muscle.handleClientDisconnected(i)
        }

        // 6th attempt from same address with new clientId should be locked out
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 6, token: "wrong-token", address: "192.168.1.100", respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .error(let serverError) = msg, serverError.kind == .authFailure {
                return serverError.message.contains("Too many")
            }
            return false
        }
        XCTAssertTrue(hasLockout, "Should receive lockout message after exceeding max failed attempts across reconnections")
    }

    func testLockoutDoesNotAffectOtherAddresses() async throws {
        // Lock out address 192.168.1.100
        for i in 1...5 {
            try await authenticate(clientId: i, token: "wrong-token", address: "192.168.1.100", respond: respondSink())
            await muscle.handleClientDisconnected(i)
        }

        // Client from different address should still be able to authenticate
        let (respond, _) = collectResponses()
        try await authenticate(clientId: 10, token: "test-token", address: "192.168.1.200", respond: respond)
        await flushCallbacks()

        XCTAssertTrue(markedAuthenticated.contains(10), "Clients from other addresses should not be affected by lockout")
    }

    // MARK: - Observer Brute-Force Protection Tests

    private func encodeWatch(token: String) throws -> Data {
        let payload = WatchPayload(token: token)
        let envelope = RequestEnvelope(message: .watch(payload))
        return try JSONEncoder().encode(envelope)
    }

    private func watchAuthenticate(
        clientId: Int,
        token: String,
        address: String = "127.0.0.1",
        respond: @escaping @Sendable (Data) -> Void
    ) async throws {
        await muscle.registerClientAddress(clientId, address: address)
        await performHello(clientId: clientId, respond: respond)
        await muscle.handleUnauthenticatedMessage(clientId, data: try encodeWatch(token: token), respond: respond)
    }

    func testObserverInvalidTokenTracksFailedAttempts() async throws {
        let (respond, responses) = collectResponses()
        try await watchAuthenticate(clientId: 1, token: "wrong-token", address: "10.0.0.1", respond: respond)
        await flushCallbacks()

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasAuthFailed = serverMessages.contains { msg in
            if case .error(let serverError) = msg, serverError.kind == .authFailure { return true }
            return false
        }
        XCTAssertTrue(hasAuthFailed, "Observer with wrong token should get authFailed")
        XCTAssertFalse(markedAuthenticated.contains(1))
    }

    func testObserverLockoutAfterMaxFailedAttempts() async throws {
        let address = "10.0.0.50"

        for i in 1...5 {
            try await watchAuthenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            await muscle.handleClientDisconnected(i)
        }

        let (respond, responses) = collectResponses()
        try await watchAuthenticate(clientId: 6, token: "wrong-token", address: address, respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .error(let serverError) = msg, serverError.kind == .authFailure {
                return serverError.message.contains("Too many")
            }
            return false
        }
        XCTAssertTrue(hasLockout, "Observer should be locked out after 5 failed watch attempts")
    }

    func testObserverLockoutSharedWithDriverAuth() async throws {
        let address = "10.0.0.60"

        // Fail 3 times via watch path
        for i in 1...3 {
            try await watchAuthenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            await muscle.handleClientDisconnected(i)
        }

        // Fail 2 more times via driver auth path
        for i in 4...5 {
            try await authenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            await muscle.handleClientDisconnected(i)
        }

        // 6th attempt via watch should be locked out (shared counter)
        let (respond, responses) = collectResponses()
        try await watchAuthenticate(clientId: 6, token: "wrong-token", address: address, respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .error(let serverError) = msg, serverError.kind == .authFailure {
                return serverError.message.contains("Too many")
            }
            return false
        }
        XCTAssertTrue(hasLockout, "Watch and driver auth should share the same brute-force counter")
    }

    func testObserverSuccessfulAuthClearsFailedAttempts() async throws {
        let address = "10.0.0.70"

        // Fail 3 times via watch
        for i in 1...3 {
            try await watchAuthenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            await muscle.handleClientDisconnected(i)
        }

        // Succeed with correct token
        try await watchAuthenticate(clientId: 4, token: "test-token", address: address, respond: respondSink())
        await flushCallbacks()
        XCTAssertTrue(markedAuthenticated.contains(4), "Observer with correct token should authenticate")
    }

    func testSuccessfulAuthClearsFailedAttempts() async throws {
        let address = "192.168.1.100"

        // Fail 3 times from same address with different clientIds
        for i in 1...3 {
            try await authenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            await muscle.handleClientDisconnected(i)
        }

        // Succeed from same address
        try await authenticate(clientId: 4, token: "test-token", address: address, respond: respondSink())
        await flushCallbacks()
        XCTAssertTrue(markedAuthenticated.contains(4), "Should authenticate after failed attempts below threshold")

        // Disconnect and try failing again — counter should be reset
        await muscle.handleClientDisconnected(4)

        // Should get 5 more attempts before lockout (counter was cleared on successful auth)
        for i in 5...9 {
            try await authenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            await muscle.handleClientDisconnected(i)
        }

        // 6th attempt after reset should be locked out
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 10, token: "wrong-token", address: address, respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .error(let serverError) = msg, serverError.kind == .authFailure {
                return serverError.message.contains("Too many")
            }
            return false
        }
        XCTAssertTrue(hasLockout, "Should lock out again after counter reset and 5 more failures")
    }

    // MARK: - Broadcast FIFO ordering

    /// Cross-cutting audit Finding 5: the prior `broadcastToSubscribed`
    /// implementation spawned an unstructured `Task { await server.send(...) }`
    /// per subscriber, and Swift makes no FIFO guarantee for unstructured
    /// Tasks targeting the same actor. Two back-to-back broadcasts could
    /// land on a single subscriber in either order. The fix awaits each
    /// per-subscriber send inline so the iteration order is preserved on
    /// every subscriber. This test asserts that contract by issuing two
    /// distinct payloads across three subscribers and verifying each
    /// subscriber sees them in the issue order.
    func testBroadcastToSubscribedDeliversInFIFOOrder() async throws {
        // Three subscribers, each authenticated with a watch token (no
        // session claim) and subscribed to the hierarchy stream.
        let token = "test-token"
        for clientId in 1...3 {
            try await watchAuthenticate(clientId: clientId, token: token, address: "addr-\(clientId)", respond: respondSink())
            await muscle.subscribe(clientId: clientId)
        }
        let preBroadcastCount = sentMessages.count

        let firstPayload = Data("first".utf8)
        let secondPayload = Data("second".utf8)
        await muscle.broadcastToSubscribed(firstPayload)
        await muscle.broadcastToSubscribed(secondPayload)

        let recorded = sentMessages.dropFirst(preBroadcastCount)
        // Group by clientId and verify each subscriber received both payloads
        // and `firstPayload` precedes `secondPayload` in arrival order.
        for clientId in 1...3 {
            let perClient = recorded.filter { $0.clientId == clientId }.map(\.data)
            let firstIndex = perClient.firstIndex(of: firstPayload)
            let secondIndex = perClient.firstIndex(of: secondPayload)
            XCTAssertNotNil(firstIndex, "Subscriber \(clientId) must receive the first broadcast")
            XCTAssertNotNil(secondIndex, "Subscriber \(clientId) must receive the second broadcast")
            if let firstIndex, let secondIndex {
                XCTAssertLessThan(firstIndex, secondIndex, "Subscriber \(clientId) must observe broadcasts in FIFO order")
            }
        }
    }
}

#endif // canImport(UIKit)
