import XCTest
@testable import ButtonHeist
import TheScore

final class TheHandoffMessageTests: XCTestCase {

    // MARK: - .info

    @ButtonHeistActor
    func testInfoSetsServerInfoAndCallsOnConnected() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedInfo: ServerInfo?
        handoff.onConnected = { receivedInfo = $0 }

        let info = makeServerInfo()
        handoff.handleServerMessage(.info(info), requestId: nil)

        XCTAssertEqual(handoff.serverInfo?.appName, "TestApp")
        XCTAssertEqual(receivedInfo?.appName, "TestApp")
    }

    @ButtonHeistActor
    func testInfoAutoSubscribeSendsSubscriptionAndInitialInterfaceRequest() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConn = MockConnection()
        mockConn.serverInfo = makeServerInfo()
        handoff.autoSubscribe = true
        handoff.makeConnection = { _, _, _ in mockConn }

        handoff.connect(to: device)

        // After connect, the mock emits .info which triggers autoSubscribe sends
        let sentTypes = mockConn.sent.map { $0.0 }
        XCTAssertTrue(sentTypes.contains(where: {
            if case .subscribe = $0 { return true }
            return false
        }))
        XCTAssertTrue(sentTypes.contains(where: {
            if case .requestInterface = $0 { return true }
            return false
        }))
        XCTAssertFalse(sentTypes.contains(where: {
            if case .requestScreen = $0 { return true }
            return false
        }))
    }

    @ButtonHeistActor
    func testInfoNoAutoSubscribeDoesNotSend() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConn = MockConnection()
        mockConn.serverInfo = makeServerInfo()
        handoff.autoSubscribe = false
        handoff.makeConnection = { _, _, _ in mockConn }

        handoff.connect(to: device)

        // Only the authenticate message should be sent, no subscribe/requestInterface/requestScreen
        let hasSubscribe = mockConn.sent.contains(where: {
            if case .subscribe = $0.0 { return true }
            return false
        })
        XCTAssertFalse(hasSubscribe)
    }

    // MARK: - .interface

    @ButtonHeistActor
    func testInterfacePushUpdatesCurrentInterface() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedPayload: Interface?
        handoff.onInterface = { payload, _ in receivedPayload = payload }

        let interface = Interface(timestamp: Date(), tree: [])
        handoff.handleServerMessage(.interface(interface), requestId: nil)

        XCTAssertNotNil(handoff.currentInterface)
        XCTAssertNotNil(receivedPayload)
    }

    @ButtonHeistActor
    func testInterfaceResponseDoesNotUpdateCurrent() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        handoff.handleServerMessage(.interface(Interface(timestamp: Date(), tree: [])),
                                    requestId: "req-1")

        XCTAssertNil(handoff.currentInterface)
    }

    // MARK: - .screen

    @ButtonHeistActor
    func testScreenPushUpdatesCurrentScreen() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedScreen: ScreenPayload?
        handoff.onScreen = { payload, _ in receivedScreen = payload }

        let screen = ScreenPayload(pngData: "abc", width: 390, height: 844)
        handoff.handleServerMessage(.screen(screen), requestId: nil)

        XCTAssertNotNil(handoff.currentScreen)
        XCTAssertNotNil(receivedScreen)
    }

    @ButtonHeistActor
    func testScreenResponseDoesNotUpdateCurrent() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        let screen = ScreenPayload(pngData: "abc", width: 390, height: 844)
        handoff.handleServerMessage(.screen(screen), requestId: "req-1")

        XCTAssertNil(handoff.currentScreen)
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

    @ButtonHeistActor
    func testAuthApprovedNilToken() async {
        let handoff = TheHandoff()
        handoff.token = "old"

        handoff.handleServerMessage(.authApproved(AuthApprovedPayload(token: nil)),
                                    requestId: nil)

        XCTAssertNil(handoff.token)
    }

    // MARK: - .sessionLocked

    @ButtonHeistActor
    func testSessionLockedTransitionsToFailed() async {
        let handoff = TheHandoff()
        var receivedPayload: SessionLockedPayload?
        handoff.onSessionLocked = { receivedPayload = $0 }

        let payload = SessionLockedPayload(message: "Session busy", activeConnections: 2)
        handoff.handleServerMessage(.sessionLocked(payload), requestId: nil)

        assertFailed(handoff.connectionPhase, failure: .sessionLocked("Session busy"))
        XCTAssertEqual(receivedPayload?.activeConnections, 2)
    }

    // MARK: - .error(authFailure)

    @ButtonHeistActor
    func testAuthFailedTransitionsToFailed() async {
        let handoff = TheHandoff()
        var receivedReason: String?
        handoff.onAuthFailed = { receivedReason = $0 }

        handoff.handleServerMessage(
            .error(ServerError(kind: .authFailure, message: "bad token")),
            requestId: nil
        )

        assertFailed(handoff.connectionPhase, failure: .authFailed("bad token"))
        XCTAssertEqual(receivedReason, "bad token")
    }

    // MARK: - .interaction

    @ButtonHeistActor
    func testInteractionCallsCallback() async {
        let handoff = TheHandoff()
        var receivedEvent: InteractionEvent?
        handoff.onInteraction = { receivedEvent = $0 }

        let event = InteractionEvent(
            timestamp: 1.5,
            command: .ping,
            result: ActionResult(success: true, method: .activate)
        )
        handoff.handleServerMessage(.interaction(event), requestId: nil)

        XCTAssertEqual(receivedEvent?.timestamp, 1.5)
    }

    // MARK: - .protocolMismatch

    @ButtonHeistActor
    func testProtocolMismatchCallsOnError() async {
        let handoff = TheHandoff()
        var receivedError: String?
        handoff.onError = { receivedError = $0 }

        let payload = ProtocolMismatchPayload(
            serverButtonHeistVersion: "2026.05.09",
            clientButtonHeistVersion: "2026.05.08"
        )
        handoff.handleServerMessage(.protocolMismatch(payload), requestId: nil)

        XCTAssertNotNil(receivedError)
        XCTAssertTrue(receivedError?.contains("buttonHeistVersion mismatch") == true)
        XCTAssertTrue(receivedError?.contains("2026.05.09") == true)
        XCTAssertTrue(receivedError?.contains("2026.05.08") == true)
    }

    @ButtonHeistActor
    func testRequestScopedErrorDoesNotFailConnection() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var receivedError: String?
        var requestError: (serverError: ServerError, requestId: String)?
        handoff.onError = { receivedError = $0 }
        handoff.onRequestError = { serverError, requestId in
            requestError = (serverError, requestId)
        }
        handoff.handleServerMessage(.info(makeServerInfo()), requestId: nil)

        handoff.handleServerMessage(.error(ServerError(kind: .general, message: "Response too large")), requestId: "request-1")

        XCTAssertNil(receivedError)
        XCTAssertEqual(requestError?.serverError.kind, .general)
        XCTAssertEqual(requestError?.serverError.message, "Response too large")
        XCTAssertEqual(requestError?.requestId, "request-1")
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
        handoff.handleServerMessage(.pong, requestId: nil)
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
        handoff.handleServerMessage(.recordingStopped, requestId: nil)
        assertDisconnected(handoff.connectionPhase)
        XCTAssertEqual(handoff.recordingPhase, .idle)
    }

    @ButtonHeistActor
    func testRecordingStoppedTransitionsRecordingToIdle() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        handoff.handleServerMessage(.recordingStarted, requestId: nil)

        handoff.handleServerMessage(.recordingStopped, requestId: nil)

        XCTAssertEqual(handoff.recordingPhase, .idle)
    }

    // MARK: - .recording

    @ButtonHeistActor
    func testRecordingStartedTransitions() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        var startedCalled = false
        handoff.onRecordingStarted = { startedCalled = true }

        handoff.handleServerMessage(.recordingStarted, requestId: nil)

        XCTAssertEqual(handoff.recordingPhase, .recording)
        XCTAssertTrue(startedCalled)
    }

    @ButtonHeistActor
    func testRecordingPayloadTransitionsToIdle() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        // Start recording first
        handoff.handleServerMessage(.recordingStarted, requestId: nil)
        XCTAssertEqual(handoff.recordingPhase, .recording)

        var receivedPayload: RecordingPayload?
        handoff.onRecording = { receivedPayload = $0 }

        let payload = RecordingPayload(
            videoData: "base64video", width: 390, height: 844,
            duration: 5.0, frameCount: 40, fps: 8,
            startTime: Date(), endTime: Date(),
            stopReason: .manual
        )
        handoff.handleServerMessage(.recording(payload), requestId: nil)

        XCTAssertEqual(handoff.recordingPhase, .idle)
        XCTAssertNotNil(receivedPayload)
    }

    @ButtonHeistActor
    func testRecordingErrorTransitionsToIdle() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        handoff.handleServerMessage(.recordingStarted, requestId: nil)

        var receivedError: String?
        handoff.onRecordingError = { receivedError = $0 }

        handoff.handleServerMessage(
            .error(ServerError(kind: .recording, message: "capture failed")),
            requestId: nil
        )

        XCTAssertEqual(handoff.recordingPhase, .idle)
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
        handoff.handleServerMessage(.pong, requestId: nil)
        XCTAssertEqual(handoff.missedPongCount, 0)

        // Subsequent ticks count again from zero.
        XCTAssertEqual(handoff.tickKeepalive(), 1)
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
        handoff.onDisconnected = { _ in disconnectFired = true }

        // Eight ticks across ~40 simulated seconds — well past the
        // 30-second force-disconnect threshold. A pong arrives between
        // every ping, exactly mirroring what the server's fast path does.
        for _ in 0..<8 {
            let count = handoff.tickKeepalive()
            XCTAssertLessThan(count, 6, "missedPongCount must never reach the disconnect threshold while pongs are flowing")
            handoff.handleServerMessage(.pong, requestId: nil)
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
        handoff.onDisconnected = { _ in disconnectedCalled = true }

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
            screenHeight: 844
        )
    }
}
