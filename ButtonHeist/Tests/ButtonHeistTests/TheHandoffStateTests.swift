import ButtonHeistTestSupport
import Network
import os
import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

@ButtonHeistActor
final class ManualReconnectSleeper {
    private var continuations: [CheckedContinuation<Bool, Never>] = []
    private(set) var sleepCallCount = 0

    func sleep(_: TimeInterval) async -> Bool {
        sleepCallCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeNext(returning result: Bool = true) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: result)
    }
}

final class TheHandoffStateTests: XCTestCase {

    @ButtonHeistActor
    static func makeReachableTransportConnection() -> MockConnection {
        let connection = MockConnection()
        connection.emitTransportReadyOnConnect = true
        return connection
    }

    @ButtonHeistActor
    func testInitialState() async {
        let handoff = TheHandoff()

        XCTAssertTrue(handoff.discoveryLifecycle.discoveredDevices.isEmpty)
        XCTAssertNil(handoff.connectionLifecycle.connectedDevice)
        XCTAssertNil(handoff.connectionLifecycle.serverInfo)
        XCTAssertFalse(handoff.discoveryLifecycle.isDiscovering)
        assertDisconnected(handoff.connectionPhase)
    }

    @ButtonHeistActor
    func testTransportReadyHookDoesNotMarkHandoffConnected() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        mock.onTransportReady?()

        assertConnecting(handoff.connectionPhase, device: device)
        XCTAssertNil(handoff.connectionLifecycle.connectedDevice)
    }

    @ButtonHeistActor
    func testDisconnectClearsState() async {
        let handoff = TheHandoff()

        handoff.disconnect()

        XCTAssertNil(handoff.connectionLifecycle.connectedDevice)
        XCTAssertNil(handoff.connectionLifecycle.serverInfo)
        assertDisconnected(handoff.connectionPhase)
    }

    @ButtonHeistActor
    func testStopDiscoveryClearsFlag() async {
        let handoff = TheHandoff()

        handoff.startDiscovery()
        handoff.stopDiscovery()

        XCTAssertFalse(handoff.discoveryLifecycle.isDiscovering)
    }

    @ButtonHeistActor
    func testServerErrorSetsConnectionPhaseFailed() async {
        let handoff = TheHandoff()
        let serverError = ServerError(kind: .general, message: "something went wrong")

        handoff.handleServerMessage(.error(serverError), requestId: nil)

        assertFailed(handoff.connectionPhase, failure: .serverFailure(serverError))
        XCTAssertEqual(handoff.connectionLifecycle.diagnosticFailure, .serverFailure(serverError))
    }

    @ButtonHeistActor
    func testServerHelloSendsClientHelloFromHandoff() async {
        let handoff = TheHandoff()
        let mock = connectMockHandoff(handoff)

        handoff.handleServerMessage(.serverHello, requestId: nil)

        XCTAssertEqual(mock.sent.map { $0.0.wireType }, [.clientHello])
    }

    @ButtonHeistActor
    func testServerHelloSendsClientHelloBeforeHandoffIsConnected() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        handoff.handleServerMessage(.serverHello, requestId: nil)

        assertConnecting(handoff.connectionPhase, device: device)
        XCTAssertEqual(mock.sent.map { $0.0.wireType }, [.clientHello])
    }

    @ButtonHeistActor
    func testAuthRequiredSendsConfiguredTokenAndDriverFromHandoff() async {
        let handoff = TheHandoff()
        handoff.authToken = "test-token"
        handoff.driverID = "test-driver"
        let mock = connectMockHandoff(handoff)

        handoff.handleServerMessage(.authRequired, requestId: nil)

        guard case .authenticate(let payload) = mock.sent.first?.0 else {
            return XCTFail("Expected Handoff to send authenticate, got \(String(describing: mock.sent.first?.0))")
        }
        XCTAssertEqual(payload.token, "test-token")
        XCTAssertEqual(payload.driverId, "test-driver")
        XCTAssertEqual(mock.sent.count, 1)
    }

    @ButtonHeistActor
    func testAuthRequiredSendsAuthenticateBeforeHandoffIsConnected() async {
        let handoff = TheHandoff()
        handoff.authToken = "test-token"
        handoff.driverID = "test-driver"
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        handoff.handleServerMessage(.authRequired, requestId: nil)

        assertConnecting(handoff.connectionPhase, device: device)
        guard case .authenticate(let payload) = mock.sent.first?.0 else {
            return XCTFail("Expected Handoff to send authenticate, got \(String(describing: mock.sent.first?.0))")
        }
        XCTAssertEqual(payload.token, "test-token")
        XCTAssertEqual(payload.driverId, "test-driver")
        XCTAssertEqual(mock.sent.count, 1)
    }

    @ButtonHeistActor
    func testAuthRequiredWithoutTokenFailsWithoutSendingAuthenticate() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)

        handoff.handleServerMessage(.authRequired, requestId: nil)

        assertFailed(handoff.connectionPhase, failure: .disconnected(.missingToken))
        XCTAssertTrue(mock.sent.isEmpty)
        XCTAssertEqual(mock.disconnectCount, 1)
    }

    @ButtonHeistActor
    func testAuthFailureMessageFailsHandoffAndClosesTransport() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)

        handoff.handleServerMessage(
            .error(ServerError(kind: .authFailure, message: "bad token")),
            requestId: nil
        )

        assertFailed(handoff.connectionPhase, failure: .disconnected(.authFailed("bad token")))
        XCTAssertEqual(mock.disconnectCount, 1)
    }

    @ButtonHeistActor
    func testSessionLockedFailsHandoffAndClosesTransport() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)
        let payload = SessionLockedPayload(message: "locked by another driver", activeConnections: 1)

        handoff.handleServerMessage(.sessionLocked(payload), requestId: nil)

        assertFailed(handoff.connectionPhase, failure: .disconnected(.sessionLocked(payload.message)))
        XCTAssertEqual(mock.disconnectCount, 1)
    }

    @ButtonHeistActor
    func testProtocolMismatchFailsHandoffAndClosesTransport() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)

        handoff.handleServerMessage(
            .protocolMismatch(ProtocolMismatchPayload(
                serverButtonHeistVersion: "0.0.0",
                clientButtonHeistVersion: buttonHeistVersion
            )),
            requestId: nil
        )

        assertFailed(handoff.connectionPhase, failure: .disconnected(.buttonHeistVersionMismatch(
            serverVersion: "0.0.0",
            clientVersion: buttonHeistVersion
        )))
        XCTAssertEqual(mock.disconnectCount, 1)
    }

    @ButtonHeistActor
    func testObservedTransportDisconnectDoesNotCloseTransportAgain() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)

        mock.onEvent?(.disconnected(.serverClosed))

        assertDisconnected(handoff.connectionPhase)
        XCTAssertEqual(mock.disconnectCount, 0)
    }

    @ButtonHeistActor
    func testPongResetsKeepaliveCounterAndForwardsRequestScopedPong() async {
        let handoff = TheHandoff()
        _ = connectMockHandoff(handoff)
        var forwarded: [(ServerMessage, RequestID?)] = []
        handoff.onServerMessage = { message, requestId in
            forwarded.append((message, requestId))
        }

        XCTAssertEqual(handoff.tickKeepalive(), 1)
        XCTAssertEqual(handoff.tickKeepalive(), 2)

        handoff.handleServerMessage(.pong(PongPayload(bundleIdentifier: "com.buttonheist.test")), requestId: "ping-1")

        XCTAssertEqual(handoff.connectionLifecycle.missedPongCount, 0)
        XCTAssertEqual(forwarded.count, 1)
        XCTAssertEqual(forwarded.first?.1, "ping-1")
        guard case .pong = forwarded.first?.0 else {
            return XCTFail("Expected request-scoped pong to be forwarded")
        }
    }

    @ButtonHeistActor
    func testConnectionEventForwardsTypedSendFailureRequestID() async {
        let handoff = TheHandoff()
        let connection = connectMockHandoff(handoff)
        let requestID: RequestID = "request-1"
        var received: (DeviceSendFailure, RequestID?)?
        handoff.onSendFailure = { failure, eventRequestID in
            received = (failure, eventRequestID)
        }

        connection.onEvent?(.sendFailed(.notConnected, requestId: requestID))

        XCTAssertEqual(received?.0, .notConnected)
        XCTAssertEqual(received?.1, requestID)
    }

    @ButtonHeistActor
    func testKeepaliveToleratesDebuggerLengthMissedPongGapThenRecovers() async {
        let handoff = TheHandoff()
        _ = connectMockHandoff(handoff)

        let sixtySecondPauseTicks = 12
        XCTAssertLessThan(sixtySecondPauseTicks, handoff.keepalive.maxMissedPongs)

        for count in 1...sixtySecondPauseTicks {
            XCTAssertEqual(handoff.tickKeepalive(), count)
            assertConnected(handoff.connectionPhase)
        }

        handoff.handleServerMessage(.pong(PongPayload(bundleIdentifier: "com.buttonheist.test")), requestId: nil)

        XCTAssertEqual(handoff.connectionLifecycle.missedPongCount, 0)
        XCTAssertEqual(handoff.tickKeepalive(), 1)
        assertConnected(handoff.connectionPhase)
    }

    @ButtonHeistActor
    func testStaleKeepaliveAttemptCannotDisconnectReplacementSession() async {
        let handoff = TheHandoff()
        let firstDevice = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let firstMock = connectMockHandoff(handoff, device: firstDevice)
        guard case .connected(let firstSession) = handoff.connectionPhase else {
            return XCTFail("Expected first session to connect")
        }

        let secondDevice = DiscoveredDevice(host: "127.0.0.1", port: 4321)
        let secondMock = MockConnection()
        handoff.makeConnection = { _ in secondMock }
        handoff.connect(to: secondDevice)

        XCTAssertEqual(firstMock.disconnectCount, 1)
        assertConnected(handoff.connectionPhase, device: secondDevice)

        XCTAssertEqual(handoff.tickKeepalive(expectedAttemptID: firstSession.attemptID), 0)
        handoff.forceDisconnect(expectedAttemptID: firstSession.attemptID)

        XCTAssertEqual(secondMock.disconnectCount, 0)
        XCTAssertTrue(secondMock.sent.isEmpty)
        assertConnected(handoff.connectionPhase, device: secondDevice)
    }

    @ButtonHeistActor
    func testMultipleDisconnectsSafe() async {
        let handoff = TheHandoff()

        handoff.disconnect()
        handoff.disconnect()
        handoff.disconnect()

        assertDisconnected(handoff.connectionPhase)
    }

    // MARK: - waitForConnectionResult continuation

    @ButtonHeistActor
    func testWaitForConnectionResultReturnsImmediatelyWhenAlreadyConnected() async throws {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.serverInfo = ServerInfo(
            appName: "TestApp",
            bundleIdentifier: "com.test",
            deviceName: "Simulator",
            systemVersion: "26.1",
            screenWidth: 402,
            screenHeight: 874,
            instanceId: "test-session",
            instanceIdentifier: "test",
            listeningPort: 49152,
            tlsActive: true
        )
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        XCTAssertTrue(handoff.connectionLifecycle.isConnected)

        // Already connected — should return immediately without throwing.
        try await handoff.waitForConnectionResult(timeout: 5)
    }

    @ButtonHeistActor
    func testWaitForConnectionResultThrowsWhenAlreadyFailed() async {
        let handoff = TheHandoff()
        let serverError = ServerError(kind: .general, message: "boom")
        // Drive into .failed state via a server error.
        handoff.handleServerMessage(
            .error(serverError),
            requestId: nil
        )
        assertFailed(handoff.connectionPhase, failure: .serverFailure(serverError))

        do {
            try await handoff.waitForConnectionResult(timeout: 5)
            XCTFail("Expected HandoffConnectionError to be thrown")
        } catch let error as HandoffConnectionError {
            guard case .serverFailure(let failure) = error else {
                return XCTFail("Expected .serverFailure, got \(error)")
            }
            XCTAssertEqual(failure, serverError)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @ButtonHeistActor
    func testWaitForConnectionResultResumesOnConnectedTransition() async throws {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        // Don't auto-connect — caller will trigger the .connected event manually
        // so we can verify the continuation wakes on the transition.
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        // Phase is now .connecting; waiter should suspend.
        let waitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 5)
        }

        // Yield once so the waiter registers its continuation before we fire
        // the .connected event.
        await Task.yield()

        // Fire the connected transition.
        mock.onEvent?(.connected)
        XCTAssertTrue(handoff.connectionLifecycle.isConnected)

        try await waitTask.value
    }

    @ButtonHeistActor
    func testWaitForConnectionResultPropagatesCancellationError() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []  // Stays in .connecting until cancelled
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)

        let waitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }

        // Yield so the continuation registers before we cancel.
        await Task.yield()
        waitTask.cancel()

        do {
            try await waitTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    @ButtonHeistActor
    func testCancellingOneWaiterDoesNotCancelSiblingWaiter() async throws {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)

        let cancelledWaitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }
        let liveWaitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }
        await Task.yield()

        cancelledWaitTask.cancel()
        do {
            try await cancelledWaitTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        mock.onEvent?(.connected)

        try await liveWaitTask.value
        assertConnected(handoff.connectionPhase, device: device)
    }

    @ButtonHeistActor
    func testShortTimeoutWaiterDoesNotPoisonLongWaiter() async throws {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)

        let shortWaitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 0.05)
        }
        let longWaitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }
        await Task.yield()

        do {
            try await shortWaitTask.value
            XCTFail("Expected timeout")
        } catch let error as HandoffConnectionError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Expected timeout, got \(error)")
        }

        assertConnecting(handoff.connectionPhase, device: device)
        mock.onEvent?(.connected)

        try await longWaitTask.value
        assertConnected(handoff.connectionPhase, device: device)
    }

    @ButtonHeistActor
    func testWaitForConnectionResultResumesOnFailedTransition() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)

        let waitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }

        // Yield so the continuation registers.
        await Task.yield()

        // Drive into .failed via an auth-failure server error.
        handoff.handleServerMessage(
            .error(ServerError(kind: .authFailure, message: "bad token")),
            requestId: nil
        )

        do {
            try await waitTask.value
            XCTFail("Expected auth failure")
        } catch let error as HandoffConnectionError {
            guard case .disconnected(.authFailed(let reason, hint: _)) = error else {
                return XCTFail("Expected auth-failed disconnect, got \(error)")
            }
            XCTAssertEqual(reason, "bad token")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @ButtonHeistActor
    func testTerminalConnectionFailureResolvesAllLiveWaitersForAttempt() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)

        let firstWaitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }
        let secondWaitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }
        await Task.yield()

        mock.onEvent?(.disconnected(.missingToken))

        for waitTask in [firstWaitTask, secondWaitTask] {
            do {
                try await waitTask.value
                XCTFail("Expected disconnect failure")
            } catch let error as HandoffConnectionError {
                XCTAssertEqual(error, .disconnected(.missingToken))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testTerminalAttemptIgnoresLateRequestScopedError() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let serverError = ServerError(kind: .general, message: "connection failed")
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        var receivedMessage: ServerMessage?
        var receivedRequestID: RequestID?
        handoff.onServerMessage = { message, requestID in
            receivedMessage = message
            receivedRequestID = requestID
        }

        handoff.connect(to: device)
        mock.onEvent?(.connected)
        mock.onEvent?(.message(
            .error(serverError),
            requestId: nil
        ))
        assertFailed(handoff.connectionPhase, failure: .serverFailure(serverError))

        mock.onEvent?(.message(
            .error(ServerError(kind: .general, message: "request failed")),
            requestId: "request-1"
        ))

        XCTAssertNil(receivedMessage)
        XCTAssertNil(receivedRequestID)
        assertFailed(handoff.connectionPhase, failure: .serverFailure(serverError))
    }

    @ButtonHeistActor
    func testTerminalAttemptIgnoresLateRequestScopedObservationPayloads() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let serverError = ServerError(kind: .general, message: "connection failed")
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        var receivedMessages: [(message: ServerMessage, requestID: RequestID?)] = []
        handoff.onServerMessage = { message, requestID in
            receivedMessages.append((message, requestID))
        }

        handoff.connect(to: device)
        mock.onEvent?(.connected)
        mock.onEvent?(.message(
            .error(serverError),
            requestId: nil
        ))
        assertFailed(handoff.connectionPhase, failure: .serverFailure(serverError))

        let interface = makeTestInterface(
            elements: [makeTestHeistElement(label: "Title")],
            timestamp: Date(timeIntervalSince1970: 100)
        )
        mock.onEvent?(.message(
            .interface(interface),
            requestId: "interface-1"
        ))

        let screen = ScreenPayload(
            pngData: "base64png",
            width: 390,
            height: 844,
            timestamp: Date(timeIntervalSince1970: 200),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 200), tree: [])
        )
        mock.onEvent?(.message(
            .screen(screen),
            requestId: "screen-1"
        ))

        XCTAssertTrue(receivedMessages.isEmpty)
        assertFailed(handoff.connectionPhase, failure: .serverFailure(serverError))
    }

    @ButtonHeistActor
    func testTerminalAttemptIgnoresStateMutatingRequestScopedMessages() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let serverError = ServerError(kind: .general, message: "connection failed")
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)
        mock.onEvent?(.connected)
        mock.onEvent?(.message(
            .error(serverError),
            requestId: nil
        ))

        mock.onEvent?(.message(
            .info(TheFenceFixtures.testServerInfo),
            requestId: "request-1"
        ))

        XCTAssertNil(handoff.connectionLifecycle.serverInfo)
        assertFailed(handoff.connectionPhase, failure: .serverFailure(serverError))
    }

    @ButtonHeistActor
    func testWaitForConnectionResultPreservesDisconnectCause() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = [
            .disconnected(.missingToken),
        ]
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)

        do {
            try await handoff.waitForConnectionResult(timeout: 30)
            XCTFail("Expected disconnect failure")
        } catch let error as HandoffConnectionError {
            guard case .disconnected(let reason) = error else {
                return XCTFail("Expected .disconnected, got \(error)")
            }
            XCTAssertEqual(reason, .missingToken)
            XCTAssertEqual(error.diagnostic.details.code, .tlsMissingToken)
            XCTAssertEqual(error.failureCode, KnownFailureCode.tlsMissingToken.rawValue)
            XCTAssertEqual(error.phase, .tls)
            XCTAssertFalse(error.retryable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @ButtonHeistActor
    func testSendAfterLocalDisconnectFailsTyped() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        handoff.makeConnection = { _ in mock }
        handoff.connect(to: device)
        handoff.disconnect()

        let outcome = handoff.send(.ping, requestId: "late")

        guard case .failed(.notConnected) = outcome else {
            return XCTFail("Expected notConnected send failure, got \(outcome)")
        }
        XCTAssertTrue(mock.sent.isEmpty, "Local disconnect must close the send path")
    }

    /// Regression test: an early synchronous cancel — before any `Task.yield()`
    /// — must propagate `CancellationError`. Without the early-cancel guard
    /// inside the continuation body, the cancellation handler hops to the
    /// actor and finds an empty awaiter list, then the body runs and appends
    /// the now-orphaned continuation, which only resolves on phase transition
    /// or timeout.
    @ButtonHeistActor
    func testWaitForConnectionResultPropagatesEarlyCancellation() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []  // Stay in .connecting indefinitely
        handoff.makeConnection = { _ in mock }

        handoff.connect(to: device)

        let waitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }
        // Cancel synchronously, before any yield, so the cancel races with
        // continuation registration.
        waitTask.cancel()

        do {
            try await waitTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    /// Regression test: an idempotent `transitionToDisconnected` (when phase
    /// was already `.disconnected` or `.failed`) must not resume awaiters.
    /// We verify this by reaching .failed (which under the previous
    /// implementation also resumed awaiters from any prior phase), then
    /// confirming a subsequent disconnect() preserves the failed-phase
    /// expectation rather than triggering a second resume cycle.
    @ButtonHeistActor
    func testWaitForConnectionResultIgnoresIdempotentDisconnect() async throws {
        let handoff = TheHandoff()
        let serverError = ServerError(kind: .general, message: "boom")

        // Drive into .failed (server error) — this is a terminal phase.
        handoff.handleServerMessage(
            .error(serverError),
            requestId: nil
        )
        assertFailed(handoff.connectionPhase, failure: .serverFailure(serverError))

        // Calling disconnect() now is a no-op transition (.failed → .disconnected
        // is technically a phase change but, importantly, awaiters from any
        // prior wait are not re-resumed). It must be safe.
        handoff.disconnect()
        assertDisconnected(handoff.connectionPhase)

        // A second idempotent disconnect (.disconnected → .disconnected) must
        // also be safe and must not resume any awaiter.
        handoff.disconnect()
        assertDisconnected(handoff.connectionPhase)

        // Now register an awaiter — it should fast-path-throw on .disconnected,
        // not get a stale resume from the prior idempotent transitions.
        do {
            try await handoff.waitForConnectionResult(timeout: 30)
            XCTFail("Expected fast-path throw on .disconnected")
        } catch is HandoffConnectionError {
            // Expected.
        }
    }

    /// Regression test: when `connect(to: device)` is called while phase is
    /// already `.disconnected`, the replacement teardown is a no-op transition
    /// (`.disconnected → .disconnected`). The subsequent `.connecting →
    /// .connected` transition should resolve the awaiter with success — the
    /// awaiter must not have been spuriously failed by the no-op teardown.
    @ButtonHeistActor
    func testWaitForConnectionResultDoesNotFailOnReconnectDisconnect() async throws {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        // Mock that stays in .connecting until we manually fire .connected.
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _ in mock }

        // Phase starts at .disconnected. `connect()` first runs replacement
        // teardown (a no-op .disconnected → .disconnected transition), then
        // transitions to .connecting.
        handoff.connect(to: device)

        let waitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }
        await Task.yield()

        // Drive into .connected — awaiter must resolve with success.
        mock.onEvent?(.connected)

        try await waitTask.value
        XCTAssertTrue(handoff.connectionLifecycle.isConnected)
    }

}

@ButtonHeistActor
final class HandoffTestSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !isSignalled else { return }
        isSignalled = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

final class FakeDiscoveryBrowser: DeviceDiscoveryBrowsing {
    private struct State {
        var onStateChanged: (@Sendable (DeviceDiscoveryBrowserState) -> Void)?
        var startCount = 0
        var cancelCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var startCount: Int {
        state.withLock { $0.startCount }
    }

    var cancelCount: Int {
        state.withLock { $0.cancelCount }
    }

    func start(
        queue: DispatchQueue,
        onResultsChanged: @escaping @Sendable (Set<NWBrowser.Result>, Set<NWBrowser.Result.Change>) -> Void,
        onStateChanged: @escaping @Sendable (DeviceDiscoveryBrowserState) -> Void
    ) {
        state.withLock { state in
            state.onStateChanged = onStateChanged
            state.startCount += 1
        }
    }

    func cancel() {
        state.withLock { $0.cancelCount += 1 }
    }

    func emit(_ browserState: DeviceDiscoveryBrowserState) {
        let onStateChanged = state.withLock { $0.onStateChanged }
        onStateChanged?(browserState)
    }
}
