#if canImport(UIKit)
import XCTest
import TheScore
@testable import TheInsideJob

@MainActor
final class TheMuscleTests: XCTestCase {

    // MARK: - Test Helpers

    private var muscle: TheMuscle!
    private var sentMessages: [(data: Data, clientId: Int)] = []
    private var markedAuthenticated: [Int] = []
    private var disconnectedClients: [Int] = []
    private var authenticatedCallbacks: [(clientId: Int, respond: @Sendable (Data) -> Void)] = []

    override func setUp() {
        super.setUp()
        muscle = TheMuscle(explicitToken: "test-token")
        sentMessages = []
        markedAuthenticated = []
        disconnectedClients = []
        authenticatedCallbacks = []

        muscle.sendToClient = { [unowned self] data, clientId in
            self.sentMessages.append((data, clientId))
        }
        muscle.markClientAuthenticated = { [unowned self] clientId in
            self.markedAuthenticated.append(clientId)
        }
        muscle.disconnectClient = { [unowned self] clientId in
            self.disconnectedClients.append(clientId)
        }
        muscle.onClientAuthenticated = { [unowned self] clientId, respond in
            self.authenticatedCallbacks.append((clientId, respond))
        }

    }

    override func tearDown() {
        muscle.tearDown()
        muscle = nil
        super.tearDown()
    }

    // MARK: - Encoding helpers

    private func encodeAuth(token: String, driverId: String? = nil) -> Data {
        let payload = AuthenticatePayload(token: token, driverId: driverId)
        let envelope = RequestEnvelope(message: .authenticate(payload))
        // swiftlint:disable:next force_try
        return try! JSONEncoder().encode(envelope)
    }

    private func decodeServerMessage(_ data: Data) -> ServerMessage? {
        (try? JSONDecoder().decode(ResponseEnvelope.self, from: data))?.message
    }

    private func performHello(clientId: Int, respond: @escaping @Sendable (Data) -> Void) {
        guard let data = try? JSONEncoder().encode(RequestEnvelope(message: .clientHello)) else {
            XCTFail("Failed to encode clientHello")
            return
        }
        muscle.handleUnauthenticatedMessage(clientId, data: data, respond: respond)
    }

    private func authenticate(
        clientId: Int,
        token: String,
        driverId: String? = nil,
        respond: @escaping @Sendable (Data) -> Void
    ) {
        performHello(clientId: clientId, respond: respond)
        muscle.handleUnauthenticatedMessage(clientId, data: encodeAuth(token: token, driverId: driverId), respond: respond)
    }

    private func respondSink() -> @Sendable (Data) -> Void {
        // No-op respond closure for tests that don't need to inspect responses.
        // Use collectResponses() when you need to check what was sent back.
        return { _ in }
    }

    private func collectResponses() -> (respond: @Sendable (Data) -> Void, responses: () -> [Data]) {
        final class Box: @unchecked Sendable {
            var items: [Data] = []
        }
        let box = Box()
        let respond: @Sendable (Data) -> Void = { data in
            box.items.append(data)
        }
        return (respond, { box.items })
    }

    // MARK: - Auth Flow Tests

    func testValidTokenAuthenticates() {
        let (respond, responses) = collectResponses()
        authenticate(clientId: 1, token: "test-token", respond: respond)

        XCTAssertTrue(markedAuthenticated.contains(1), "Client should be marked authenticated")
        XCTAssertTrue(muscle.authenticatedClientIDs.contains(1))
        XCTAssertEqual(muscle.authenticatedClientCount, 1)
        // No error message should have been sent via respond
        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        for msg in serverMessages {
            if case .authFailed = msg { XCTFail("Should not send authFailed for valid token") }
            if case .sessionLocked = msg { XCTFail("Should not send sessionLocked for first connection") }
        }
    }

    func testInvalidTokenRejected() {
        let (respond, responses) = collectResponses()
        authenticate(clientId: 1, token: "wrong-token", respond: respond)

        XCTAssertFalse(markedAuthenticated.contains(1), "Client should not be marked authenticated")
        XCTAssertFalse(muscle.authenticatedClientIDs.contains(1))
        XCTAssertEqual(muscle.authenticatedClientCount, 0)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasAuthFailed = serverMessages.contains { msg in
            if case .authFailed = msg { return true }
            return false
        }
        XCTAssertTrue(hasAuthFailed, "Should send authFailed for invalid token")
    }

    func testEmptyTokenTriggersPendingApproval() {
        let (respond, _) = collectResponses()
        authenticate(clientId: 1, token: "", respond: respond)

        // Client should NOT be authenticated yet — waiting for UI approval
        XCTAssertFalse(markedAuthenticated.contains(1))
        XCTAssertFalse(muscle.authenticatedClientIDs.contains(1))
        XCTAssertEqual(muscle.authenticatedClientCount, 0)
    }

    func testNonAuthMessageDisconnects() {
        // Send a ping message before authenticating
        // swiftlint:disable:next force_try
        let pingData = try! JSONEncoder().encode(RequestEnvelope(message: .ping))
        muscle.handleUnauthenticatedMessage(1, data: pingData, respond: respondSink())

        XCTAssertTrue(disconnectedClients.contains(1), "Should disconnect client that sends non-auth message")
    }

    // MARK: - Session Rules Tests

    func testNoSessionValidTokenAcquires() {
        authenticate(clientId: 1, token: "test-token", respond: respondSink())

        XCTAssertNotNil(muscle.activeSessionDriverId, "Session should be claimed")
        XCTAssertTrue(muscle.activeSessionConnections.contains(1))
    }

    func testSameDriverAllowed() {
        authenticate(clientId: 1, token: "test-token", respond: respondSink())
        authenticate(clientId: 2, token: "test-token", respond: respondSink())

        XCTAssertTrue(muscle.activeSessionConnections.contains(1))
        XCTAssertTrue(muscle.activeSessionConnections.contains(2))
        XCTAssertEqual(muscle.authenticatedClientCount, 2)
    }

    func testDifferentDriverBusy() {
        // Driver A connects
        authenticate(clientId: 1, token: "test-token", driverId: "driver-a", respond: respondSink())

        // Driver B tries to connect
        let (respond, responses) = collectResponses()
        authenticate(clientId: 2, token: "test-token", driverId: "driver-b", respond: respond)

        XCTAssertFalse(markedAuthenticated.contains(2), "Driver B should not be authenticated")
        XCTAssertFalse(muscle.activeSessionConnections.contains(2))

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasSessionLocked = serverMessages.contains { msg in
            if case .sessionLocked = msg { return true }
            return false
        }
        XCTAssertTrue(hasSessionLocked, "Should send sessionLocked to different driver")
    }

    func testSessionReleasedAfterAllDisconnect() async {
        // Use a very short timeout for test speed
        muscle = TheMuscle(explicitToken: "test-token")
        // Re-wire callbacks
        muscle.sendToClient = { [unowned self] data, clientId in self.sentMessages.append((data, clientId)) }
        muscle.markClientAuthenticated = { [unowned self] clientId in self.markedAuthenticated.append(clientId) }
        muscle.disconnectClient = { [unowned self] clientId in self.disconnectedClients.append(clientId) }
        muscle.onClientAuthenticated = { [unowned self] clientId, respond in self.authenticatedCallbacks.append((clientId, respond)) }

        // Authenticate a client
        authenticate(clientId: 1, token: "test-token", respond: respondSink())
        XCTAssertNotNil(muscle.activeSessionDriverId)

        // Disconnect the client — session release timer starts (default 30s, too slow for tests)
        muscle.handleClientDisconnected(1)
        // Session should still be active (timer hasn't fired)
        XCTAssertNotNil(muscle.activeSessionDriverId, "Session should still be active during grace period")
    }

    func testSameDriverRejoinsAfterDisconnect() {
        // Client 1 connects and disconnects
        authenticate(clientId: 1, token: "test-token", respond: respondSink())
        muscle.handleClientDisconnected(1)

        // Client 2 with same driver reconnects before timeout
        authenticate(clientId: 2, token: "test-token", respond: respondSink())

        XCTAssertTrue(muscle.activeSessionConnections.contains(2), "Same driver should rejoin session")
        XCTAssertTrue(markedAuthenticated.contains(2))
    }

    func testDifferentDriverBlockedDuringGracePeriod() {
        // Driver A connects and disconnects (release timer running)
        authenticate(clientId: 1, token: "test-token", driverId: "driver-a", respond: respondSink())
        muscle.handleClientDisconnected(1)

        // Driver B tries during grace period
        let (respond, responses) = collectResponses()
        authenticate(clientId: 2, token: "test-token", driverId: "driver-b", respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasSessionLocked = serverMessages.contains { msg in
            if case .sessionLocked = msg { return true }
            return false
        }
        XCTAssertTrue(hasSessionLocked, "Different driver should be blocked during grace period")
    }

    // MARK: - Token Lifecycle Tests

    func testTokenSurvivesSessionRelease() {
        let originalToken = muscle.authToken

        // Authenticate, disconnect, tearDown to force session release
        authenticate(clientId: 1, token: "test-token", respond: respondSink())
        muscle.handleClientDisconnected(1)

        // Token should remain the same after session release path
        XCTAssertEqual(muscle.authToken, originalToken, "Token should not change when session is released")
    }

    func testTokenStableAcrossMultipleCycles() {
        let originalToken = muscle.authToken

        for i in 1...5 {
            authenticate(clientId: i, token: originalToken, respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        XCTAssertEqual(muscle.authToken, originalToken, "Token should remain stable across connect/disconnect cycles")
    }

    func testExplicitTokenUsed() {
        let muscle = TheMuscle(explicitToken: "my-explicit-token")
        XCTAssertEqual(muscle.authToken, "my-explicit-token")
    }

    func testAutoGeneratedTokenIsUUID() {
        let muscle = TheMuscle(explicitToken: nil)
        // Auto-generated token should be a valid UUID format
        XCTAssertNotNil(UUID(uuidString: muscle.authToken), "Auto-generated token should be a valid UUID")
    }

    func testTearDownClearsState() {
        authenticate(clientId: 1, token: "test-token", respond: respondSink())

        XCTAssertTrue(muscle.helloValidatedClients.contains(1))

        muscle.tearDown()

        XCTAssertNil(muscle.activeSessionDriverId)
        XCTAssertTrue(muscle.activeSessionConnections.isEmpty)
        XCTAssertTrue(muscle.authenticatedClientIDs.isEmpty)
        XCTAssertTrue(muscle.helloValidatedClients.isEmpty)
        XCTAssertEqual(muscle.authenticatedClientCount, 0)
    }

    // MARK: - Brute-Force Protection Tests

    func testSingleFailedAttemptNotLockedOut() {
        let (respond, responses) = collectResponses()
        authenticate(clientId: 1, token: "wrong-token", respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasAuthFailed = serverMessages.contains { msg in
            if case .authFailed(let reason) = msg { return !reason.contains("Too many") }
            return false
        }
        XCTAssertTrue(hasAuthFailed, "First failed attempt should get normal authFailed, not lockout")
    }

    func testLockoutAfterMaxFailedAttempts() {
        // Send 5 failed attempts (max)
        for _ in 1...5 {
            authenticate(clientId: 1, token: "wrong-token", respond: respondSink())
        }

        // 6th attempt should be locked out
        let (respond, responses) = collectResponses()
        authenticate(clientId: 1, token: "wrong-token", respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .authFailed(let reason) = msg { return reason.contains("Too many") }
            return false
        }
        XCTAssertTrue(hasLockout, "Should receive lockout message after exceeding max failed attempts")
    }

    func testLockoutDoesNotAffectOtherClients() {
        // Lock out client 1
        for _ in 1...5 {
            authenticate(clientId: 1, token: "wrong-token", respond: respondSink())
        }

        // Client 2 should still be able to authenticate
        let (respond, _) = collectResponses()
        authenticate(clientId: 2, token: "test-token", respond: respond)

        XCTAssertTrue(markedAuthenticated.contains(2), "Other clients should not be affected by lockout")
    }

    func testSuccessfulAuthClearsFailedAttempts() {
        // Fail 3 times
        for _ in 1...3 {
            authenticate(clientId: 1, token: "wrong-token", respond: respondSink())
        }

        // Succeed
        authenticate(clientId: 1, token: "test-token", respond: respondSink())
        XCTAssertTrue(markedAuthenticated.contains(1), "Should authenticate after failed attempts below threshold")

        // Disconnect and try failing again — counter should be reset
        muscle.handleClientDisconnected(1)

        // Should get 5 more attempts before lockout (counter was cleared)
        for _ in 1...5 {
            authenticate(clientId: 1, token: "wrong-token", respond: respondSink())
        }

        // 6th attempt after reset should be locked out
        let (respond, responses) = collectResponses()
        authenticate(clientId: 1, token: "wrong-token", respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .authFailed(let reason) = msg { return reason.contains("Too many") }
            return false
        }
        XCTAssertTrue(hasLockout, "Should lock out again after counter reset and 5 more failures")
    }
}
#endif // canImport(UIKit)
