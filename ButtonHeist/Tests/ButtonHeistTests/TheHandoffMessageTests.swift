import XCTest
@testable import ButtonHeist
import TheScore

final class TheHandoffMessageTests: XCTestCase {

    // MARK: - .info

    @ButtonHeistActor
    func testInfoSetsServerInfo() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)

        let info = makeServerInfo()
        handoff.handleServerMessage(.info(info), requestId: nil)

        XCTAssertEqual(handoff.serverInfo?.appName, "TestApp")
    }

    @ButtonHeistActor
    func testInfoDoesNotSendImplicitObservationRequests() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConn = MockConnection()
        mockConn.serverInfo = makeServerInfo()
        handoff.makeConnection = { _, _, _ in mockConn }

        handoff.connect(to: device)

        let sentTypes = mockConn.sent.map { $0.0 }
        XCTAssertFalse(sentTypes.contains(where: {
            if case .requestInterface = $0 { return true }
            return false
        }))
        XCTAssertFalse(sentTypes.contains(where: {
            if case .requestScreen = $0 { return true }
            return false
        }))
    }

    // MARK: - .interface

    @ButtonHeistActor
    func testInterfacePushForwardsServerMessage() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedMessage: ServerMessage?
        var receivedRequestId: String?
        handoff.onServerMessage = { message, requestId in
            receivedMessage = message
            receivedRequestId = requestId
        }

        let interface = makeInterfacePayload()
        handoff.handleServerMessage(.interface(interface), requestId: nil)

        guard case .interface(let receivedPayload)? = receivedMessage else {
            return XCTFail("Expected interface message, got \(String(describing: receivedMessage))")
        }
        XCTAssertEqual(receivedPayload, interface)
        XCTAssertNil(receivedRequestId)
    }

    @ButtonHeistActor
    func testInterfaceResponseForwardsServerMessage() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedMessage: ServerMessage?
        var receivedRequestId: String?
        handoff.onServerMessage = { message, requestId in
            receivedMessage = message
            receivedRequestId = requestId
        }
        let interface = makeInterfacePayload()
        handoff.handleServerMessage(.interface(interface), requestId: "req-1")

        guard case .interface(let receivedPayload)? = receivedMessage else {
            return XCTFail("Expected interface message, got \(String(describing: receivedMessage))")
        }
        XCTAssertEqual(receivedPayload, interface)
        XCTAssertEqual(receivedRequestId, "req-1")
    }

    // MARK: - .screen

    @ButtonHeistActor
    func testScreenPushForwardsServerMessage() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedMessage: ServerMessage?
        var receivedRequestId: String?
        handoff.onServerMessage = { message, requestId in
            receivedMessage = message
            receivedRequestId = requestId
        }

        let screen = makeScreenPayload()
        handoff.handleServerMessage(.screen(screen), requestId: nil)

        guard case .screen(let receivedScreen)? = receivedMessage else {
            return XCTFail("Expected screen message, got \(String(describing: receivedMessage))")
        }
        assertScreenPayload(receivedScreen, equals: screen)
        XCTAssertNil(receivedRequestId)
    }

    @ButtonHeistActor
    func testScreenResponseForwardsServerMessage() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedMessage: ServerMessage?
        var receivedRequestId: String?
        handoff.onServerMessage = { message, requestId in
            receivedMessage = message
            receivedRequestId = requestId
        }
        let screen = makeScreenPayload()
        handoff.handleServerMessage(.screen(screen), requestId: "req-1")

        guard case .screen(let receivedScreen)? = receivedMessage else {
            return XCTFail("Expected screen message, got \(String(describing: receivedMessage))")
        }
        assertScreenPayload(receivedScreen, equals: screen)
        XCTAssertEqual(receivedRequestId, "req-1")
    }

    // MARK: - .authApproved

    @ButtonHeistActor
    func testAuthApprovedUpdatesToken() async {
        let handoff = TheHandoff()
        var approvedToken: String?
        handoff.onAuthApproved = { approvedToken = $0 }

        handoff.handleServerMessage(.authApproved(AuthApprovedPayload(token: "new-token")),
                                    requestId: nil)

        XCTAssertEqual(handoff.token, "new-token")
        XCTAssertEqual(approvedToken, "new-token")
    }

    // MARK: - .sessionLocked

    @ButtonHeistActor
    func testSessionLockedTransitionsToFailed() async throws {
        let handoff = TheHandoff()

        let payload = SessionLockedPayload(
            message: "Session busy; owner driver id: driver-a; active connections: 2; remaining timeout: 10s.",
            activeConnections: 2
        )
        handoff.handleServerMessage(.sessionLocked(payload), requestId: nil)

        assertFailed(handoff.connectionPhase, failure: .disconnected(.sessionLocked(payload.message)))
    }

    // MARK: - .error(authFailure)

    @ButtonHeistActor
    func testAuthFailedTransitionsToFailed() async {
        let handoff = TheHandoff()

        handoff.handleServerMessage(
            .error(ServerError(kind: .authFailure, message: "bad token")),
            requestId: nil
        )

        assertFailed(handoff.connectionPhase, failure: .disconnected(.authFailed("bad token")))
    }

    // MARK: - .protocolMismatch

    @ButtonHeistActor
    func testProtocolMismatchTransitionsToFailed() async {
        let handoff = TheHandoff()

        let payload = ProtocolMismatchPayload(
            serverButtonHeistVersion: "2026.05.09",
            clientButtonHeistVersion: "2026.05.08"
        )
        handoff.handleServerMessage(.protocolMismatch(payload), requestId: nil)

        guard case .failed(.disconnected(.protocolMismatch(let message))) = handoff.connectionPhase else {
            return XCTFail("Expected protocol mismatch failure, got \(handoff.connectionPhase)")
        }
        XCTAssertTrue(message.contains("Button Heist version mismatch"))
        XCTAssertTrue(message.contains("app/Inside Job is 2026.05.09"))
        XCTAssertTrue(message.contains("client/CLI/MCP is 2026.05.08"))
        XCTAssertTrue(message.contains("2026.05.09"))
        XCTAssertTrue(message.contains("2026.05.08"))
    }

    @ButtonHeistActor
    func testRequestScopedErrorDoesNotFailConnection() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedMessage: ServerMessage?
        var receivedRequestId: String?
        handoff.onServerMessage = { message, requestId in
            receivedMessage = message
            receivedRequestId = requestId
        }
        handoff.handleServerMessage(.info(makeServerInfo()), requestId: nil)

        handoff.handleServerMessage(.error(ServerError(kind: .general, message: "Response too large")), requestId: "request-1")

        guard case .error(let requestError)? = receivedMessage else {
            return XCTFail("Expected error message, got \(String(describing: receivedMessage))")
        }
        XCTAssertEqual(requestError.kind, .general)
        XCTAssertEqual(requestError.message, "Response too large")
        XCTAssertEqual(receivedRequestId, "request-1")
        if case .failed = handoff.connectionPhase {
            XCTFail("Request-scoped error should not fail the connection")
        }
    }

    // MARK: - .status

    @ButtonHeistActor
    func testStatusDoesNotMutateState() async {
        let handoff = TheHandoff()

        let payload = StatusPayload(
            identity: StatusIdentity(
                appName: "Test", bundleIdentifier: "com.test",
                appBuild: "1", deviceName: "iPhone",
                systemVersion: "17.0", buttonHeistVersion: "0.2.0"
            ),
            session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
        )
        handoff.handleServerMessage(.status(payload), requestId: nil)

        // Status is log-only; no state change should occur
        assertDisconnected(handoff.connectionPhase)
        XCTAssertNil(handoff.serverInfo)
    }

    // MARK: - No-op messages

    @ButtonHeistActor
    func testServerHelloDoesNotMutateState() async {
        let handoff = TheHandoff()
        handoff.handleServerMessage(.serverHello, requestId: nil)
        assertDisconnected(handoff.connectionPhase)
    }

    @ButtonHeistActor
    func testPongDoesNotMutateState() async {
        let handoff = TheHandoff()
        handoff.handleServerMessage(.pong(), requestId: nil)
        assertDisconnected(handoff.connectionPhase)
    }

    @ButtonHeistActor
    func testAuthRequiredDoesNotMutateState() async {
        let handoff = TheHandoff()
        handoff.handleServerMessage(.authRequired, requestId: nil)
        assertDisconnected(handoff.connectionPhase)
    }

    @ButtonHeistActor
    func testRecordingStoppedWhileDisconnectedIsNoOp() async {
        let handoff = TheHandoff()
        var receivedEvent: RecordingEvent?
        handoff.onRecordingEvent = { receivedEvent = $0 }

        handoff.handleServerMessage(.recordingStopped, requestId: nil)

        assertDisconnected(handoff.connectionPhase)
        XCTAssertNil(receivedEvent)
    }

    @ButtonHeistActor
    func testRecordingStoppedForwardsStoppedEvent() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedEvent: RecordingEvent?
        handoff.onRecordingEvent = { receivedEvent = $0 }

        handoff.handleServerMessage(.recordingStopped, requestId: nil)

        guard case .stopped? = receivedEvent else {
            return XCTFail("Expected stopped recording event, got \(String(describing: receivedEvent))")
        }
    }

    // MARK: - .recording

    @ButtonHeistActor
    func testRecordingStartedForwardsStartedEvent() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedEvent: RecordingEvent?
        handoff.onRecordingEvent = { receivedEvent = $0 }

        handoff.handleServerMessage(.recordingStarted, requestId: nil)

        guard case .started? = receivedEvent else {
            return XCTFail("Expected started recording event, got \(String(describing: receivedEvent))")
        }
    }

    @ButtonHeistActor
    func testRecordingPayloadForwardsCompletedEvent() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)

        var receivedPayload: RecordingPayload?
        handoff.onRecordingEvent = { event in
            if case .completed(let payload) = event {
                receivedPayload = payload
            }
        }

        let payload = RecordingPayload(
            videoData: "base64video", width: 390, height: 844,
            duration: 5.0, frameCount: 40, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .manual
        )
        handoff.handleServerMessage(.recording(payload), requestId: nil)

        XCTAssertNotNil(receivedPayload)
    }

    @ButtonHeistActor
    func testRecordingErrorForwardsFailedEvent() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)

        var receivedError: String?
        handoff.onRecordingEvent = { event in
            if case .failed(let message) = event {
                receivedError = message
            }
        }

        handoff.handleServerMessage(
            .error(ServerError(kind: .recording, message: "capture failed")),
            requestId: nil
        )

        XCTAssertEqual(receivedError, "capture failed")
    }

    // MARK: - Keepalive / pong handling
    //
    // Regression: a recording with `--max-duration 5` tore the connection
    // down ~25s after finalize started because the client was incrementing
    // its missed-pong counter every keepalive tick but never decrementing
    // it. Pongs were silently swallowed in DeviceConnection.handleMessage
    // and never reached TheHandoff. After 6 missed pongs (30s) the
    // keepalive force-disconnected — exactly when the server was finishing
    // its AVAssetWriter flush and trying to send the recording payload.

    @ButtonHeistActor
    func testPongResetsMissedPongCountWhileConnected() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)

        // Simulate three keepalive ticks without server reply.
        XCTAssertEqual(handoff.tickKeepalive(), 1)
        XCTAssertEqual(handoff.tickKeepalive(), 2)
        XCTAssertEqual(handoff.tickKeepalive(), 3)

        // Server replies. The counter must drop back to zero.
        handoff.handleServerMessage(.pong(), requestId: nil)
        XCTAssertEqual(handoff.missedPongCount, 0)

        // Subsequent ticks count again from zero.
        XCTAssertEqual(handoff.tickKeepalive(), 1)
    }

    @ButtonHeistActor
    func testRequestScopedPongForwardsToPendingTrackers() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedMessage: ServerMessage?
        var receivedRequestId: String?
        handoff.onServerMessage = { message, requestId in
            receivedMessage = message
            receivedRequestId = requestId
        }

        let payload = PongPayload(appName: "MockApp", bundleIdentifier: "com.test.mock", serverTimestampMs: 1_700_000)
        handoff.handleServerMessage(.pong(payload), requestId: "ping-1")

        XCTAssertEqual(handoff.missedPongCount, 0)
        XCTAssertEqual(receivedRequestId, "ping-1")
        guard case .pong(let receivedPayload)? = receivedMessage else {
            return XCTFail("Expected forwarded pong, got \(String(describing: receivedMessage))")
        }
        XCTAssertEqual(receivedPayload, payload)
    }

    @ButtonHeistActor
    func testKeepaliveCounterClearsAcrossReconnect() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockOne = MockConnection()
        handoff.makeConnection = { _, _, _ in mockOne }
        handoff.connect(to: device)

        // Accumulate missed pongs on the first session.
        XCTAssertEqual(handoff.tickKeepalive(), 1)
        XCTAssertEqual(handoff.tickKeepalive(), 2)
        XCTAssertEqual(handoff.missedPongCount, 2)

        // Reconnect (the session is rebuilt). The counter must be back to
        // zero because it now lives inside ConnectedSession; a stale
        // top-level field used to leak into the next session.
        let mockTwo = MockConnection()
        handoff.makeConnection = { _, _, _ in mockTwo }
        handoff.connect(to: device)
        XCTAssertEqual(handoff.missedPongCount, 0)
    }

    @ButtonHeistActor
    func testTickKeepaliveIsNoOpWhenNotConnected() async {
        let handoff = TheHandoff()
        XCTAssertEqual(handoff.tickKeepalive(), 0)
        XCTAssertEqual(handoff.missedPongCount, 0)
    }

    /// Regression: while the server is finalizing a recording it answers
    /// every ping via the off-MainActor fast path. The client must process
    /// each pong promptly so its counter can stay below the
    /// `maxMissedPongs` threshold for the full finalize window. Drives a
    /// realistic ping/pong cadence and asserts no force-disconnect ever
    /// fires.
    @ButtonHeistActor
    func testKeepaliveSurvivesRecordingFinalizeWindowWhenPongsArrive() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var disconnectFired = false
        handoff.onConnectionStateChanged = { state in
            if case .disconnected = state {
                disconnectFired = true
            }
        }

        // Eight ticks across ~40 simulated seconds — well past the
        // 30-second force-disconnect threshold. A pong arrives between
        // every ping, exactly mirroring what the server's fast path does.
        for _ in 0..<8 {
            let count = handoff.tickKeepalive()
            XCTAssertLessThan(count, 6, "missedPongCount must never reach the disconnect threshold while pongs are flowing")
            handoff.handleServerMessage(.pong(), requestId: nil)
            XCTAssertEqual(handoff.missedPongCount, 0)
        }

        XCTAssertFalse(disconnectFired, "Keepalive must not force-disconnect a connection whose pongs are arriving")
        XCTAssertTrue(handoff.isConnected)
    }

    // MARK: - forceDisconnect

    @ButtonHeistActor
    func testForceDisconnectWhenNotConnectedIsNoOp() async {
        let handoff = TheHandoff()
        var disconnectedCalled = false
        handoff.onConnectionStateChanged = { state in
            if case .disconnected = state {
                disconnectedCalled = true
            }
        }

        handoff.forceDisconnect()

        XCTAssertFalse(disconnectedCalled)
    }

    // MARK: - Helpers

    private func makeServerInfo() -> ServerInfo {
        ServerInfo(
            appName: "TestApp",
            bundleIdentifier: "com.test",
            deviceName: "iPhone",
            systemVersion: "17.0",
            screenWidth: 390,
            screenHeight: 844,
            instanceId: "test-session",
            instanceIdentifier: "test",
            listeningPort: 49152,
            tlsActive: true
        )
    }

    private func makeInterfacePayload() -> Interface {
        makeReceiptTestInterface(
            [
                HeistElement(
                    heistId: "continue_button",
                    description: "Continue",
                    label: "Continue",
                    value: nil,
                    identifier: "continue",
                    traits: [.button],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 120,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: 1_234)
        )
    }

    private func makeScreenPayload() -> ScreenPayload {
        ScreenPayload(
            pngData: "base64png",
            width: 390,
            height: 844,
            timestamp: Date(timeIntervalSince1970: 5_678),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 5_678), tree: [])
        )
    }

    private func assertScreenPayload(
        _ received: ScreenPayload?,
        equals expected: ScreenPayload,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(received?.pngData, expected.pngData, file: file, line: line)
        XCTAssertEqual(received?.width, expected.width, file: file, line: line)
        XCTAssertEqual(received?.height, expected.height, file: file, line: line)
        XCTAssertEqual(received?.timestamp, expected.timestamp, file: file, line: line)
    }
}
