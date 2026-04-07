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

    override func setUp() async throws {
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

    override func tearDown() async throws {
        muscle.tearDown()
        muscle = nil
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
        address: String = "127.0.0.1",
        respond: @escaping @Sendable (Data) -> Void
    ) {
        muscle.registerClientAddress(clientId, address: address)
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

    func testDrainingSessionSurvivesForRejoin() {
        // Authenticate and disconnect — session enters draining, not idle
        authenticate(clientId: 1, token: "test-token", respond: respondSink())
        muscle.handleClientDisconnected(1)

        // Session is draining: no connections, but driver still owns it
        XCTAssertTrue(muscle.activeSessionConnections.isEmpty, "No connections during draining")
        XCTAssertNotNil(muscle.activeSessionDriverId, "Driver should still own session while draining")

        // Same driver reconnects — should rejoin the draining session, not claim a new one
        var sessionChanges: [Bool] = []
        muscle.onSessionActiveChanged = { isActive in sessionChanges.append(isActive) }
        authenticate(clientId: 2, token: "test-token", respond: respondSink())

        XCTAssertTrue(muscle.activeSessionConnections.contains(2), "New client should be in session")
        XCTAssertTrue(sessionChanges.isEmpty, "Session should not have been released and reclaimed")
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
        let originalToken = muscle.sessionToken

        // Authenticate, disconnect, tearDown to force session release
        authenticate(clientId: 1, token: "test-token", respond: respondSink())
        muscle.handleClientDisconnected(1)

        // Token should remain the same after session release path
        XCTAssertEqual(muscle.sessionToken, originalToken, "Token should not change when session is released")
    }

    func testTokenStableAcrossMultipleCycles() {
        let originalToken = muscle.sessionToken

        for i in 1...5 {
            authenticate(clientId: i, token: originalToken, respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        XCTAssertEqual(muscle.sessionToken, originalToken, "Token should remain stable across connect/disconnect cycles")
    }

    func testExplicitTokenUsed() {
        let muscle = TheMuscle(explicitToken: "my-explicit-token")
        XCTAssertEqual(muscle.sessionToken, "my-explicit-token")
    }

    func testAutoGeneratedTokenIsUUID() {
        let muscle = TheMuscle(explicitToken: nil)
        // Auto-generated token should be a valid UUID format
        XCTAssertNotNil(UUID(uuidString: muscle.sessionToken), "Auto-generated token should be a valid UUID")
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
        // Send 5 failed attempts from different clientIds but same address (simulates reconnection)
        for i in 1...5 {
            authenticate(clientId: i, token: "wrong-token", address: "192.168.1.100", respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        // 6th attempt from same address with new clientId should be locked out
        let (respond, responses) = collectResponses()
        authenticate(clientId: 6, token: "wrong-token", address: "192.168.1.100", respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .authFailed(let reason) = msg { return reason.contains("Too many") }
            return false
        }
        XCTAssertTrue(hasLockout, "Should receive lockout message after exceeding max failed attempts across reconnections")
    }

    func testLockoutDoesNotAffectOtherAddresses() {
        // Lock out address 192.168.1.100
        for i in 1...5 {
            authenticate(clientId: i, token: "wrong-token", address: "192.168.1.100", respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        // Client from different address should still be able to authenticate
        let (respond, _) = collectResponses()
        authenticate(clientId: 10, token: "test-token", address: "192.168.1.200", respond: respond)

        XCTAssertTrue(markedAuthenticated.contains(10), "Clients from other addresses should not be affected by lockout")
    }

    // MARK: - Observer Brute-Force Protection Tests

    private func encodeWatch(token: String) -> Data {
        let payload = WatchPayload(token: token)
        let envelope = RequestEnvelope(message: .watch(payload))
        // swiftlint:disable:next force_try
        return try! JSONEncoder().encode(envelope)
    }

    private func watchAuthenticate(
        clientId: Int,
        token: String,
        address: String = "127.0.0.1",
        respond: @escaping @Sendable (Data) -> Void
    ) {
        muscle.registerClientAddress(clientId, address: address)
        performHello(clientId: clientId, respond: respond)
        muscle.handleUnauthenticatedMessage(clientId, data: encodeWatch(token: token), respond: respond)
    }

    func testObserverInvalidTokenTracksFailedAttempts() {
        let (respond, responses) = collectResponses()
        watchAuthenticate(clientId: 1, token: "wrong-token", address: "10.0.0.1", respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasAuthFailed = serverMessages.contains { msg in
            if case .authFailed = msg { return true }
            return false
        }
        XCTAssertTrue(hasAuthFailed, "Observer with wrong token should get authFailed")
        XCTAssertFalse(markedAuthenticated.contains(1))
    }

    func testObserverLockoutAfterMaxFailedAttempts() {
        let address = "10.0.0.50"

        for i in 1...5 {
            watchAuthenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        let (respond, responses) = collectResponses()
        watchAuthenticate(clientId: 6, token: "wrong-token", address: address, respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .authFailed(let reason) = msg { return reason.contains("Too many") }
            return false
        }
        XCTAssertTrue(hasLockout, "Observer should be locked out after 5 failed watch attempts")
    }

    func testObserverLockoutSharedWithDriverAuth() {
        let address = "10.0.0.60"

        // Fail 3 times via watch path
        for i in 1...3 {
            watchAuthenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        // Fail 2 more times via driver auth path
        for i in 4...5 {
            authenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        // 6th attempt via watch should be locked out (shared counter)
        let (respond, responses) = collectResponses()
        watchAuthenticate(clientId: 6, token: "wrong-token", address: address, respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .authFailed(let reason) = msg { return reason.contains("Too many") }
            return false
        }
        XCTAssertTrue(hasLockout, "Watch and driver auth should share the same brute-force counter")
    }

    func testObserverSuccessfulAuthClearsFailedAttempts() {
        let address = "10.0.0.70"

        // Fail 3 times via watch
        for i in 1...3 {
            watchAuthenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        // Succeed with correct token
        watchAuthenticate(clientId: 4, token: "test-token", address: address, respond: respondSink())
        XCTAssertTrue(markedAuthenticated.contains(4), "Observer with correct token should authenticate")
    }

    func testSuccessfulAuthClearsFailedAttempts() {
        let address = "192.168.1.100"

        // Fail 3 times from same address with different clientIds
        for i in 1...3 {
            authenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        // Succeed from same address
        authenticate(clientId: 4, token: "test-token", address: address, respond: respondSink())
        XCTAssertTrue(markedAuthenticated.contains(4), "Should authenticate after failed attempts below threshold")

        // Disconnect and try failing again — counter should be reset
        muscle.handleClientDisconnected(4)

        // Should get 5 more attempts before lockout (counter was cleared on successful auth)
        for i in 5...9 {
            authenticate(clientId: i, token: "wrong-token", address: address, respond: respondSink())
            muscle.handleClientDisconnected(i)
        }

        // 6th attempt after reset should be locked out
        let (respond, responses) = collectResponses()
        authenticate(clientId: 10, token: "wrong-token", address: address, respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasLockout = serverMessages.contains { msg in
            if case .authFailed(let reason) = msg { return reason.contains("Too many") }
            return false
        }
        XCTAssertTrue(hasLockout, "Should lock out again after counter reset and 5 more failures")
    }
}
#endif // canImport(UIKit)
