#if canImport(UIKit)
import ButtonHeistTestSupport
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
    private var disconnectedClientsStorage: [Int] = []
    private var authenticatedCallbacksStorage: [(clientId: Int, respond: SocketResponseHandler)] = []
    private let lock = NSLock()

    var sentMessages: [(data: Data, clientId: Int)] { lock.withLock { sentMessagesStorage } }
    var disconnectedClients: [Int] { lock.withLock { disconnectedClientsStorage } }
    var authenticatedCallbacks: [(clientId: Int, respond: SocketResponseHandler)] {
        lock.withLock { authenticatedCallbacksStorage }
    }

    func appendSent(_ entry: (Data, Int)) { lock.withLock { sentMessagesStorage.append(entry) } }
    func appendDisconnected(_ clientId: Int) { lock.withLock { disconnectedClientsStorage.append(clientId) } }
    func appendAuthenticatedCallback(_ entry: (Int, SocketResponseHandler)) {
        lock.withLock { authenticatedCallbacksStorage.append(entry) }
    }
}

@MainActor
final class TheMuscleTests: XCTestCase {

    // MARK: - Test Helpers

    private var muscle: TheMuscle!
    private var sink: CallbackSink!

    private func makeMuscle(
        explicitToken: SessionAuthToken?,
        sessionReleaseTimeout: TimeInterval = StartupConfiguration.defaultSessionTimeout
    ) -> TheMuscle {
        TheMuscle(
            explicitToken: explicitToken,
            sessionReleaseTimeout: sessionReleaseTimeout
        )
    }

    override func setUp() async throws {
        try await super.setUp()
        muscle = makeMuscle(explicitToken: "test-token")
        sink = CallbackSink()
        await installCallbacks()
    }

    override func tearDown() async throws {
        await muscle.tearDown()
        muscle = nil
        sink = nil
        try await super.tearDown()
    }

    private var sentMessages: [(data: Data, clientId: Int)] { sink.sentMessages }
    private var disconnectedClients: [Int] { sink.disconnectedClients }
    private var authenticatedCallbacks: [(clientId: Int, respond: SocketResponseHandler)] {
        sink.authenticatedCallbacks
    }

    /// Install test callbacks. Each callback writes to the shared `CallbackSink`,
    /// which is thread-safe so the closures don't need to hop back to the harness's
    /// `@MainActor` isolation.
    private func installCallbacks() async {
        let sink = self.sink!
        let sendToClient: @Sendable (Data, Int) async -> ServerSendOutcome = { data, clientId in
            sink.appendSent((data, clientId))
            return .delivered
        }
        let disconnect: @Sendable (Int) async -> Void = { clientId in
            sink.appendDisconnected(clientId)
        }
        let onAuthenticated: @MainActor @Sendable (Int, @escaping SocketResponseHandler) async -> Void = { clientId, respond in
            sink.appendAuthenticatedCallback((clientId, respond))
        }
        await muscle.installCallbacks(
            sendToClient: sendToClient,
            disconnectClient: disconnect,
            onClientAuthenticated: onAuthenticated
        )
    }

    // MARK: - Encoding helpers

    private func encodeAuth(token: SessionAuthToken, driverId: DriverID? = nil) throws -> Data {
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

    private func performHello(clientId: Int, respond: @escaping SocketResponseHandler) async {
        guard let data = try? JSONEncoder().encode(RequestEnvelope(message: .clientHello)) else {
            XCTFail("Failed to encode clientHello")
            return
        }
        _ = await muscle.admitClientMessage(clientId, data: data, respond: respond)
    }

    private func authenticate(
        clientId: Int,
        token: SessionAuthToken,
        driverId: DriverID? = nil,
        address: String = "127.0.0.1",
        respond: @escaping SocketResponseHandler
    ) async throws {
        await muscle.registerClientAddress(clientId, address: address)
        await performHello(clientId: clientId, respond: respond)
        _ = await muscle.admitClientMessage(
            clientId,
            data: try encodeAuth(token: token, driverId: driverId),
            respond: respond
        )
    }

    private func respondSink() -> SocketResponseHandler {
        // No-op respond closure for tests that don't need to inspect responses.
        // Use collectResponses() when you need to check what was sent back.
        return { _ in .delivered }
    }

    private func collectResponses() -> (respond: SocketResponseHandler, responses: () -> [Data]) {
        // Test-only inspection box. Mutated only from within the @Sendable
        // closure that captures it; not shared across threads in practice.
        final class Box: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
            var items: [Data] = []
            let lock = NSLock()
        }
        let box = Box()
        let respond: SocketResponseHandler = { data in
            box.lock.withLock { box.items.append(data) }
            return .delivered
        }
        return (respond, { box.lock.withLock { box.items } })
    }

    /// No-op: callbacks now write to a thread-safe sink so test assertions
    /// can read synchronously after the awaited muscle call returns. Kept
    /// for call-site stability; remove once all tests are inlined.
    private func flushCallbacks() async {}

    private func yieldScheduler() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    // MARK: - Encoding

    func testEnvelopeEncodingFailureDoesNotInventFallbackMessage() async {
        let requestID: RequestID = "bad-info"
        let payload = ServerInfo(
            appName: "Test",
            bundleIdentifier: "test.bundle",
            deviceName: "Device",
            systemVersion: "1",
            screenWidth: .nan,
            screenHeight: 100,
            instanceId: "test-session",
            instanceIdentifier: "test",
            listeningPort: 49152,
            tlsActive: true
        )

        let result = await muscle.encodeEnvelope(.info(payload), requestId: requestID)

        guard case .failure(let failure) = result else {
            return XCTFail("Encoding failure should fail closed instead of synthesizing a different response shape")
        }
        XCTAssertEqual(failure.requestId, requestID)
    }

    func testExplicitErrorEnvelopeStillEncodes() async throws {
        let requestID: RequestID = "explicit-error"
        let result = await muscle.encodeEnvelope(
            .error(ServerError(kind: .general, message: "Explicit failure")),
            requestId: requestID
        )
        guard case .success(let data) = result else {
            return XCTFail("Expected explicit error envelope to encode, got \(result)")
        }

        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        XCTAssertEqual(envelope.requestId, requestID)
        guard case .error(let error) = envelope.message else {
            return XCTFail("Expected explicit error response, got \(envelope.message)")
        }
        XCTAssertEqual(error.kind, .general)
        XCTAssertEqual(error.message, "Explicit failure")
    }

    func testServerHelloResponseEnvelopeKeepsStableWireShape() async throws {
        let result = await muscle.sendServerHello(clientId: 7)

        XCTAssertEqual(result, .delivered)
        let sent = try XCTUnwrap(sentMessages.first)
        XCTAssertEqual(sent.clientId, 7)
        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: sent.data)
        XCTAssertNil(envelope.requestId)
        guard case .serverHello = envelope.message else {
            return XCTFail("Expected serverHello envelope, got \(envelope.message)")
        }
        let object = try JSONProbe(data: sent.data)
        XCTAssertEqual(try object.string("type"), ServerWireMessageType.serverHello.rawValue)
        try object.assertMissing("payload")
        XCTAssertEqual(try object.string("buttonHeistVersion"), buttonHeistVersion.description)
    }

    func testAdmissionFailureResponseEnvelopeKeepsStableWireShape() async throws {
        let (respond, responses) = collectResponses()
        let data = try JSONEncoder().encode(RequestEnvelope(requestId: "unauth-ping", message: .ping))

        _ = await muscle.admitClientMessage(1, data: data, respond: respond)

        let response = try XCTUnwrap(responses().first)
        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: response)
        XCTAssertEqual(envelope.requestId, "unauth-ping")
        guard case .error(let error) = envelope.message else {
            return XCTFail("Expected error envelope, got \(envelope.message)")
        }
        XCTAssertEqual(error.kind, .authFailure)
        XCTAssertEqual(error.message, "Authentication required before ping.")
        let object = try JSONProbe(data: response)
        XCTAssertEqual(try object.string("type"), ServerWireMessageType.error.rawValue)
        try object.assertPresent("payload")
        XCTAssertEqual(try object.string("buttonHeistVersion"), buttonHeistVersion.description)
    }

    // MARK: - Auth Flow Tests

    func testMessageRateAdmissionReturnsGeneralErrorForFirstOverLimitFrame() throws {
        var admission = TheMuscleAdmission(
            tokenSource: .configured("good-token"),
            maxFailedAttempts: 2,
            lockoutDuration: 30
        )
        let data = try JSONEncoder().encode(RequestEnvelope(message: .ping))
        let now = Date()

        for _ in 0..<MessageRateLimiter.defaultMaxMessagesPerSecond {
            _ = admission.admitClientMessage(
                1,
                data: data,
                respond: { _ in .delivered },
                at: now
            )
        }

        guard case .handled(let effects) = admission.admitClientMessage(
            1,
            data: data,
            respond: { _ in .delivered },
            at: now
        ) else {
            return XCTFail("Expected over-limit frame to be handled by admission")
        }

        XCTAssertEqual(effects.count, 2)
        guard case .log(.rateLimited(let clientId)) = effects[0] else {
            return XCTFail("Expected rate-limit log first, got \(effects[0])")
        }
        XCTAssertEqual(clientId, 1)
        guard case .sendResponse(.error(let error), let requestId, _) = effects[1] else {
            return XCTFail("Expected rate-limit response second, got \(effects[1])")
        }
        XCTAssertNil(requestId)
        XCTAssertEqual(error.kind, .general)
        XCTAssertEqual(error.message, "Rate limited: max 30 messages per second")
    }

    func testMessageRateAdmissionNotifiesOnlyOncePerWindow() throws {
        var admission = TheMuscleAdmission(
            tokenSource: .configured("good-token"),
            maxFailedAttempts: 2,
            lockoutDuration: 30
        )
        let data = try JSONEncoder().encode(RequestEnvelope(message: .ping))
        let now = Date()

        for _ in 0..<MessageRateLimiter.defaultMaxMessagesPerSecond {
            _ = admission.admitClientMessage(
                1,
                data: data,
                respond: { _ in .delivered },
                at: now
            )
        }

        guard case .handled(let firstLimit) = admission.admitClientMessage(
            1,
            data: data,
            respond: { _ in .delivered },
            at: now
        ) else {
            return XCTFail("Expected first over-limit frame to be handled")
        }
        XCTAssertEqual(firstLimit.count, 2)
        guard case .log(.rateLimited(let firstLimitClientId)) = firstLimit[0] else {
            return XCTFail("Expected first over-limit effect to log rate limiting")
        }
        XCTAssertEqual(firstLimitClientId, 1)
        guard case .sendResponse = firstLimit[1] else {
            return XCTFail("Expected first over-limit notification to send a response")
        }

        guard case .handled(let repeatedLimit) = admission.admitClientMessage(
            1,
            data: data,
            respond: { _ in .delivered },
            at: now
        ) else {
            return XCTFail("Expected repeated over-limit frame to be handled")
        }
        XCTAssertEqual(repeatedLimit.count, 1)
        guard case .log(.rateLimited(let repeatedLimitClientId)) = repeatedLimit[0] else {
            return XCTFail("Expected repeated over-limit frame to only log rate limiting")
        }
        XCTAssertEqual(repeatedLimitClientId, 1)

        guard case .handled(let nextWindow) = admission.admitClientMessage(
            1,
            data: data,
            respond: { _ in .delivered },
            at: now.addingTimeInterval(1.1)
        ) else {
            return XCTFail("Expected next-window frame to continue through normal admission")
        }
        XCTAssertEqual(nextWindow.count, 3)
        guard case .log(.unauthenticatedMessage(let clientId, let message)) = nextWindow[0] else {
            return XCTFail("Expected unauthenticated-message log first, got \(nextWindow[0])")
        }
        XCTAssertEqual(clientId, 1)
        XCTAssertEqual(message, "Authentication required before ping.")
        guard case .sendResponse(.error(let error), _, _) = nextWindow[1] else {
            return XCTFail("Expected normal pre-auth rejection after window reset")
        }
        guard case .delayedDisconnect(let disconnectClientId) = nextWindow[2] else {
            return XCTFail("Expected disconnect after response, got \(nextWindow[2])")
        }
        XCTAssertEqual(disconnectClientId, 1)
        XCTAssertEqual(error.kind, .authFailure)
        XCTAssertEqual(error.message, "Authentication required before ping.")
    }

    func testMessageRateAdmissionLimitsAuthenticatedMessagesBeforeDispatch() throws {
        var admission = TheMuscleAdmission(
            tokenSource: .configured("good-token"),
            maxFailedAttempts: 2,
            lockoutDuration: 30
        )
        let respond: SocketResponseHandler = { _ in .delivered }
        let now = Date()

        admission.registerClientAddress(1, address: "127.0.0.1")
        let helloData = try JSONEncoder().encode(RequestEnvelope(message: .clientHello))
        guard case .handled = admission.admitClientMessage(
            1,
            data: helloData,
            respond: respond,
            at: now
        ) else {
            return XCTFail("Expected client hello to be handled")
        }

        guard case .authenticate(let authentication) = admission.admitClientMessage(
            1,
            data: try encodeAuth(token: "good-token"),
            respond: respond,
            at: now
        ) else {
            return XCTFail("Expected valid token to request authentication completion")
        }
        _ = admission.completeAuthentication(authentication)

        let pingData = try JSONEncoder().encode(RequestEnvelope(message: .ping))
        let nextWindow = now.addingTimeInterval(1.1)
        for _ in 0..<MessageRateLimiter.defaultMaxMessagesPerSecond {
            guard case .admitted = admission.admitClientMessage(
                1,
                data: pingData,
                respond: respond,
                at: nextWindow
            ) else {
                return XCTFail("Expected authenticated message to reach dispatch before rate limit")
            }
        }

        guard case .handled(let effects) = admission.admitClientMessage(
            1,
            data: pingData,
            respond: respond,
            at: nextWindow
        ) else {
            return XCTFail("Expected over-limit authenticated message to be handled by admission")
        }
        XCTAssertEqual(effects.count, 2)
        guard case .log(.rateLimited(let clientId)) = effects[0] else {
            return XCTFail("Expected rate-limit log first, got \(effects[0])")
        }
        XCTAssertEqual(clientId, 1)
        guard case .sendResponse(.error(let error), let requestId, _) = effects[1] else {
            return XCTFail("Expected rate-limit response second, got \(effects[1])")
        }
        XCTAssertNil(requestId)
        XCTAssertEqual(error.kind, .general)
        XCTAssertEqual(error.message, "Rate limited: max 30 messages per second")
    }

    func testValidTokenAuthenticates() async throws {
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 1, token: "test-token", respond: respond)
        await flushCallbacks()

        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(1))
        XCTAssertEqual(connections.count, 1)
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

        let connections = await muscle.activeSessionConnections
        XCTAssertFalse(connections.contains(1))
        XCTAssertEqual(connections.count, 0)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let authFailure = serverMessages.compactMap { msg -> ServerError? in
            guard case .error(let serverError) = msg, serverError.kind == .authFailure else { return nil }
            return serverError
        }.first
        XCTAssertEqual(
            authFailure?.message,
            "Invalid token. Retry with the configured token."
        )
        XCTAssertEqual(authFailure?.recoveryHint, "Retry with the configured token.")
    }

    func testGeneratedTokenAuthenticatesWhenProvided() async throws {
        await muscle.tearDown()
        muscle = makeMuscle(explicitToken: nil)
        sink = CallbackSink()
        await installCallbacks()
        let generatedToken = await muscle.sessionToken

        try await authenticate(clientId: 1, token: generatedToken, respond: respondSink())

        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(1))
    }

    func testGeneratedTokenInvalidTokenSuggestsConfiguredToken() async throws {
        await muscle.tearDown()
        muscle = makeMuscle(explicitToken: nil)
        sink = CallbackSink()
        await installCallbacks()
        let (respond, responses) = collectResponses()

        try await authenticate(clientId: 1, token: "wrong-token", respond: respond)

        let authFailure = responses().compactMap { data -> ServerError? in
            guard case .error(let error) = decodeServerMessage(data), error.kind == .authFailure else { return nil }
            return error
        }.first
        XCTAssertEqual(
            authFailure?.message,
            "Invalid token. Retry with the configured token."
        )
        XCTAssertEqual(authFailure?.recoveryHint, "Retry with the configured token.")
    }

    func testNonAuthMessageReturnsAuthFailure() async throws {
        // Send a ping message before authenticating
        let pingData = try JSONEncoder().encode(RequestEnvelope(message: .ping))
        let (respond, responses) = collectResponses()
        _ = await muscle.admitClientMessage(1, data: pingData, respond: respond)
        await flushCallbacks()

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let authFailure = serverMessages.compactMap { message -> ServerError? in
            guard case .error(let error) = message, error.kind == .authFailure else { return nil }
            return error
        }.first
        XCTAssertEqual(authFailure?.message, "Authentication required before ping.")
    }

    func testMalformedPreAuthMessageSendsErrorBeforeDisconnect() async throws {
        let (respond, responses) = collectResponses()

        _ = await muscle.admitClientMessage(1, data: Data("not json".utf8), respond: respond)
        await flushCallbacks()

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let validationError = serverMessages.compactMap { message -> ServerError? in
            guard case .error(let error) = message, error.kind == .validationError else { return nil }
            return error
        }.first
        XCTAssertNotNil(validationError)
        XCTAssertTrue(validationError?.message.contains("Could not decode client message before authentication") == true)
        XCTAssertTrue(validationError?.message.contains("same Button Heist version") == true)
    }

    // MARK: - Session Rules Tests

    func testNoSessionValidTokenAcquires() async throws {
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())

        let driverId = await muscle.sessionOwner
        XCTAssertNotNil(driverId, "Session should be claimed")
        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(1))
    }

    func testSameDriverRejectedWhileActive() async throws {
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())

        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 2, token: "test-token", respond: respond)
        await flushCallbacks()

        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(1))
        XCTAssertFalse(connections.contains(2))
        XCTAssertEqual(connections.count, 1)

        let payload = try XCTUnwrap(
            sessionLockedPayloads(from: responses()).first,
            "A second active same-driver connection should be rejected"
        )
        XCTAssertEqual(payload.activeConnections, 1)
        XCTAssertTrue(payload.message.contains("Session is already active for this driver"))
    }

    func testDifferentDriverBusy() async throws {
        // Driver A connects
        try await authenticate(clientId: 1, token: "test-token", driverId: "driver-a", respond: respondSink())

        // Driver B tries to connect
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 2, token: "test-token", driverId: "driver-b", respond: respond)
        await flushCallbacks()

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
        let driverId = await muscle.sessionOwner
        XCTAssertNotNil(driverId)

        // Disconnect the client — session release timer starts (default 30s, too slow for tests)
        await muscle.handleClientDisconnected(1)
        // Session should still be active (timer hasn't fired)
        let driverIdAfter = await muscle.sessionOwner
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
    }

    func testDrainingSessionSurvivesForRejoin() async throws {
        // Authenticate and disconnect — session enters draining, not idle
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())
        await muscle.handleClientDisconnected(1)

        // Session is draining: no connections, but driver still owns it
        let connectionsDuringDrain = await muscle.activeSessionConnections
        XCTAssertTrue(connectionsDuringDrain.isEmpty, "No connections during draining")
        let driverIdDuringDrain = await muscle.sessionOwner
        XCTAssertNotNil(driverIdDuringDrain, "Driver should still own session while draining")
        let hasReleaseTimerDuringDrain = await muscle.hasSessionReleaseTimerForTesting
        XCTAssertTrue(hasReleaseTimerDuringDrain)

        // Same driver reconnects — should rejoin the draining session, not claim a new one.
        await installCallbacks()
        try await authenticate(clientId: 2, token: "test-token", respond: respondSink())

        let connectionsAfter = await muscle.activeSessionConnections
        let driverIdAfter = await muscle.sessionOwner
        XCTAssertTrue(connectionsAfter.contains(2), "New client should be in session")
        XCTAssertEqual(driverIdAfter, driverIdDuringDrain)
        let hasReleaseTimerAfterRejoin = await muscle.hasSessionReleaseTimerForTesting
        XCTAssertFalse(hasReleaseTimerAfterRejoin)
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

    func testDisconnectingNonSessionClientDoesNotStartReleaseTimer() async throws {
        await muscle.tearDown()
        muscle = makeMuscle(explicitToken: "test-token", sessionReleaseTimeout: 0)
        sink = CallbackSink()
        await installCallbacks()

        try await authenticate(clientId: 1, token: "test-token", driverId: "driver-a", respond: respondSink())
        await muscle.registerClientAddress(2, address: "127.0.0.1")

        await muscle.handleClientDisconnected(2)
        await yieldScheduler()

        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(1))
        let driverId = await muscle.sessionOwner
        XCTAssertEqual(driverId, .driver("driver-a"))
    }

    func testLastSessionConnectionStartsReleaseTimer() async throws {
        await muscle.tearDown()
        muscle = makeMuscle(explicitToken: "test-token", sessionReleaseTimeout: 0)
        sink = CallbackSink()
        await installCallbacks()

        try await authenticate(clientId: 1, token: "test-token", driverId: "driver-a", respond: respondSink())
        await muscle.handleClientDisconnected(1)
        await muscle.awaitSessionReleaseTimerForTesting()

        let driverId = await muscle.sessionOwner
        XCTAssertNil(driverId)
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
        let muscle = makeMuscle(explicitToken: "my-explicit-token")
        let token = await muscle.sessionToken
        XCTAssertEqual(token, "my-explicit-token")
    }

    func testAutoGeneratedTokenIsUUID() async {
        let muscle = makeMuscle(explicitToken: nil)
        let token = await muscle.sessionToken
        XCTAssertNotNil(UUID(uuidString: token.description), "Auto-generated token should be a valid UUID")
    }

    func testTearDownClearsState() async throws {
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())
        await flushCallbacks()

        let connectionsBefore = await muscle.activeSessionConnections
        XCTAssertTrue(connectionsBefore.contains(1))

        await muscle.tearDown()

        let driverId = await muscle.sessionOwner
        XCTAssertNil(driverId)
        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.isEmpty)
    }

    // MARK: - Brute-Force Protection Tests

    func testSingleFailedAttemptNotLockedOut() async throws {
        let (respond, responses) = collectResponses()
        try await authenticate(clientId: 1, token: "wrong-token", respond: respond)

        let serverMessages = responses().compactMap { decodeServerMessage($0) }
        let hasAuthFailed = serverMessages.contains { msg in
            if case .error(let serverError) = msg, serverError.kind == .authFailure {
                return !serverError.message.description.contains("Too many")
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
                return serverError.message.description.contains("Too many")
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

        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(10), "Clients from other addresses should not be affected by lockout")
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
        let connections = await muscle.activeSessionConnections
        XCTAssertTrue(connections.contains(4), "Should authenticate after failed attempts below threshold")

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
                return serverError.message.description.contains("Too many")
            }
            return false
        }
        XCTAssertTrue(hasLockout, "Should lock out again after counter reset and 5 more failures")
    }

    func testSendDataAfterClientDisconnectFailsWithoutCallingTransport() async throws {
        try await authenticate(clientId: 1, token: "test-token", respond: respondSink())
        await flushCallbacks()
        let sentBeforeDisconnect = sentMessages.count

        await muscle.handleClientDisconnected(1)

        let outcome = await muscle.sendData(Data("late-response".utf8), toClient: 1)

        guard case .failed(.clientNotFound(1)) = outcome else {
            return XCTFail("Expected clientNotFound failure, got \(outcome)")
        }
        XCTAssertEqual(
            sentMessages.count,
            sentBeforeDisconnect,
            "Closed-client sends must fail before invoking the transport closure"
        )
    }
}

#endif // canImport(UIKit)
