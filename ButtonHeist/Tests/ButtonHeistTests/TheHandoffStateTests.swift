import ButtonHeistTestSupport
import Network
import os
import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

@ButtonHeistActor
private final class ManualReconnectSleeper {
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

    // MARK: - Auto Reconnect

    @ButtonHeistActor
    func testDisableAutoReconnectCancelsReconnectRunner() async {
        let handoff = TheHandoff()
        let reconnectSleeper = ManualReconnectSleeper()
        handoff.reconnectSleeper = reconnectSleeper.sleep
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        var connectionCount = 0
        handoff.makeConnection = { _ in
            connectionCount += 1
            let mock = MockConnection()
            mock.connectEventsOverride = [
                .connected,
                .disconnected(.serverClosed),
            ]
            return mock
        }

        handoff.setupAutoReconnect(filter: "App")
        handoff.connect(to: device)

        await Task.yield()
        XCTAssertEqual(reconnectSleeper.sleepCallCount, 1)

        handoff.disableAutoReconnect()
        reconnectSleeper.resumeNext()
        await Task.yield()

        XCTAssertEqual(connectionCount, 1)
    }

    @ButtonHeistActor
    func testReplacingAutoReconnectFilterPreventsStaleReconnect() async {
        let handoff = TheHandoff()
        let reconnectSleeper = ManualReconnectSleeper()
        handoff.reconnectSleeper = reconnectSleeper.sleep
        let oldDevice = DiscoveredDevice(
            id: "old-device",
            name: "OldApp#one",
            endpoint: .hostPort(host: "127.0.0.1", port: 1111)
        )
        let newDevice = DiscoveredDevice(
            id: "new-device",
            name: "NewApp#one",
            endpoint: .hostPort(host: "127.0.0.1", port: 2222)
        )

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [oldDevice, newDevice]
        handoff.makeDiscovery = { mockDiscovery }
        handoff.startDiscovery()

        var connectedIDs: [DiscoveryDeviceID] = []
        handoff.makeConnection = { device in
            connectedIDs.append(device.id)
            let connection = MockConnection()
            connection.connectEventsOverride = connectedIDs.count == 1
                ? [.connected, .disconnected(.serverClosed)]
                : [.connected]
            return connection
        }

        handoff.setupAutoReconnect(filter: "OldApp")
        handoff.connect(to: oldDevice)
        XCTAssertEqual(connectedIDs, ["old-device"])
        await Task.yield()
        XCTAssertEqual(reconnectSleeper.sleepCallCount, 1)

        handoff.setupAutoReconnect(filter: "NewApp")
        reconnectSleeper.resumeNext()
        await Task.yield()

        XCTAssertEqual(connectedIDs, ["old-device"])
    }

    @ButtonHeistActor
    func testDisconnectEventWithEnabledPolicyTriggersReconnect() async throws {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0.01
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        let reconnected = expectation(description: "reconnect connection made")
        var connectionCount = 0
        handoff.makeConnection = { _ in
            connectionCount += 1
            let connection = MockConnection()
            if connectionCount == 1 {
                connection.connectEventsOverride = [
                    .connected,
                    .disconnected(.serverClosed),
                ]
            } else {
                connection.serverInfo = ServerInfo(
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
                reconnected.fulfill()
            }
            return connection
        }

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [device]
        handoff.makeDiscovery = { mockDiscovery }
        handoff.startDiscovery()

        handoff.setupAutoReconnect(filter: nil)

        handoff.connect(to: device)
        XCTAssertEqual(connectionCount, 1)

        await fulfillment(of: [reconnected], timeout: 5)

        XCTAssertGreaterThanOrEqual(connectionCount, 2)
    }

    @ButtonHeistActor
    func testConnectionLifecycleCancelsReplacedRunAndRejectsStaleCompletion() async {
        let lifecycle = HandoffConnectionLifecycle()
        let oldDevice = DiscoveredDevice(host: "127.0.0.1", port: 1111)
        let newDevice = DiscoveredDevice(host: "127.0.0.1", port: 2222)

        XCTAssertTrue(lifecycle.setup(filter: "OldApp"))
        guard let oldTarget = lifecycle.targetForDisconnectedDevice(oldDevice) else {
            return XCTFail("Expected old reconnect target")
        }
        guard let oldRun = lifecycle.run(target: oldTarget, operation: { _ in }) else {
            return XCTFail("Expected old reconnect run")
        }
        XCTAssertTrue(lifecycle.isReconnectRunning)

        XCTAssertTrue(lifecycle.setup(filter: "NewApp"))
        XCTAssertFalse(lifecycle.isReconnectRunning)
        XCTAssertFalse(lifecycle.finishSuccess(oldRun))
        XCTAssertFalse(lifecycle.finishFailure(oldRun, failure: .connectionFailed("stale")))

        guard let newTarget = lifecycle.targetForDisconnectedDevice(newDevice) else {
            return XCTFail("Expected new reconnect target")
        }
        guard let newRun = lifecycle.run(target: newTarget, operation: { _ in }) else {
            return XCTFail("Expected new reconnect run")
        }

        XCTAssertTrue(lifecycle.finishSuccess(newRun))
    }

    @ButtonHeistActor
    func testConnectionLifecycleRejectsDuplicateReconnectRun() async {
        let lifecycle = HandoffConnectionLifecycle()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        XCTAssertTrue(lifecycle.setup(filter: nil))
        guard let target = lifecycle.targetForDisconnectedDevice(device) else {
            return XCTFail("Expected reconnect target")
        }

        XCTAssertNotNil(lifecycle.run(target: target, operation: { _ in }))
        XCTAssertNil(lifecycle.run(target: target, operation: { _ in }))
    }

    @ButtonHeistActor
    func testConnectionLifecycleReconnectExhaustionRequiresExplicitRearming() async {
        let lifecycle = HandoffConnectionLifecycle()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let failure = HandoffConnectionError.connectionFailed("gave up")

        XCTAssertTrue(lifecycle.setup(filter: nil))
        guard let target = lifecycle.targetForDisconnectedDevice(device) else {
            return XCTFail("Expected reconnect target")
        }
        guard let run = lifecycle.run(target: target, operation: { _ in }) else {
            return XCTFail("Expected reconnect run")
        }

        XCTAssertTrue(lifecycle.finishFailure(run, failure: failure))
        assertFailed(lifecycle.phase, failure: failure)
        XCTAssertFalse(lifecycle.isReconnectRunning)
        XCTAssertFalse(lifecycle.finishSuccess(run))
        XCTAssertFalse(lifecycle.finishFailure(run, failure: .connectionFailed("again")))
        XCTAssertNil(lifecycle.targetForDisconnectedDevice(device))

        XCTAssertTrue(lifecycle.setup(filter: nil))
        XCTAssertNotNil(lifecycle.targetForDisconnectedDevice(device))
    }

    @ButtonHeistActor
    func testConnectionLifecycleReconnectSuccessRetainsOnlyFilterPolicy() async {
        let lifecycle = HandoffConnectionLifecycle()
        let firstDevice = DiscoveredDevice(host: "127.0.0.1", port: 1111)
        let secondDevice = DiscoveredDevice(host: "127.0.0.1", port: 2222)

        XCTAssertTrue(lifecycle.setup(filter: nil))
        guard let firstTarget = lifecycle.targetForDisconnectedDevice(firstDevice),
              let firstRun = lifecycle.run(target: firstTarget, operation: { _ in })
        else {
            return XCTFail("Expected first reconnect run")
        }

        XCTAssertTrue(lifecycle.finishSuccess(firstRun))

        guard let secondTarget = lifecycle.targetForDisconnectedDevice(secondDevice) else {
            return XCTFail("Expected rearmed reconnect target")
        }
        XCTAssertEqual(secondTarget.device, secondDevice)
    }

    @ButtonHeistActor
    func testRetryableDisconnectEntersConnectionLifecycleReconnectPhase() async {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 60
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        var observedPhases: [HandoffConnectionPhase] = []
        handoff.onConnectionStateChanged = { phase in
            observedPhases.append(phase)
        }

        handoff.makeConnection = { _ in
            let connection = MockConnection()
            connection.connectEventsOverride = [
                .connected,
                .disconnected(.serverClosed),
            ]
            return connection
        }

        handoff.setupAutoReconnect(filter: nil)
        handoff.connect(to: device)

        assertReconnecting(handoff.connectionPhase, device: device)
        XCTAssertEqual(handoff.connectionLifecycle.diagnosticFailure, .disconnected(.serverClosed))
        XCTAssertTrue(observedPhases.contains { phase in
            guard case .reconnecting(let attempt) = phase else { return false }
            return attempt.target.device == device
        })
        handoff.disableAutoReconnect()
    }

    @ButtonHeistActor
    func testReconnectPhaseNotifiesWhenRunIdentityChanges() async {
        let lifecycle = HandoffConnectionLifecycle()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let target = HandoffReconnectTarget(
            resolutionTarget: DeviceResolutionTarget(filter: nil),
            device: device
        )
        var phases: [HandoffConnectionPhase] = []
        lifecycle.onPhaseChanged = { phases.append($0) }

        XCTAssertTrue(lifecycle.setup(filter: nil))
        guard let firstRun = lifecycle.run(target: target, operation: { _ in }) else {
            return XCTFail("Expected first reconnect run")
        }
        XCTAssertTrue(lifecycle.finishSuccess(firstRun))
        guard let secondRun = lifecycle.run(target: target, operation: { _ in }) else {
            return XCTFail("Expected second reconnect run")
        }

        let reconnectRuns = phases.compactMap { phase -> HandoffReconnectRunContext? in
            guard case .reconnecting(let run) = phase else { return nil }
            return run
        }
        XCTAssertEqual(reconnectRuns.map(\.id), [firstRun.id, secondRun.id])
        XCTAssertEqual(reconnectRuns.map(\.target), [target, target])
    }

    @ButtonHeistActor
    func testReconnectAttemptFailurePreservesRunWithoutRepeatingPhaseNotification() async {
        let lifecycle = HandoffConnectionLifecycle()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let target = HandoffReconnectTarget(
            resolutionTarget: DeviceResolutionTarget(filter: nil),
            device: device
        )
        let failure = HandoffConnectionError.connectionFailed("retry failed")
        var phases: [HandoffConnectionPhase] = []
        lifecycle.onPhaseChanged = { phases.append($0) }

        XCTAssertTrue(lifecycle.setup(filter: nil))
        guard let run = lifecycle.run(target: target, operation: { _ in }) else {
            return XCTFail("Expected reconnect run")
        }

        lifecycle.recordAttemptFailure(failure)

        assertReconnecting(lifecycle.phase, device: device)
        XCTAssertEqual(lifecycle.diagnosticFailure, failure)
        XCTAssertEqual(phases.compactMap { phase -> UUID? in
            guard case .reconnecting(let context) = phase else { return nil }
            return context.id
        }, [run.id])
    }

    @ButtonHeistActor
    func testNonRetryableDisconnectDoesNotTriggerReconnect() async throws {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0.01
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        let disconnected = expectation(description: "disconnect event received")
        var connectionCount = 0
        handoff.makeConnection = { _ in
            connectionCount += 1
            let connection = MockConnection()
            connection.connectEventsOverride = [
                .disconnected(.missingToken),
            ]
            return connection
        }
        handoff.onConnectionStateChanged = { state in
            if case .disconnected = state {
                disconnected.fulfill()
            }
        }

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [device]
        handoff.makeDiscovery = { mockDiscovery }
        handoff.startDiscovery()
        handoff.setupAutoReconnect(filter: nil)

        handoff.connect(to: device)
        await fulfillment(of: [disconnected], timeout: 5)

        XCTAssertEqual(connectionCount, 1)
    }

    @ButtonHeistActor
    func testForceDisconnectSchedulesReconnectOnlyWhenPolicyAllows() async {
        let disabledPolicyHandoff = TheHandoff()
        let disabledPolicyDevice = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        _ = connectMockHandoff(disabledPolicyHandoff, device: disabledPolicyDevice)

        disabledPolicyHandoff.forceDisconnect()

        assertDisconnected(disabledPolicyHandoff.connectionPhase)

        let enabledPolicyHandoff = TheHandoff()
        let enabledPolicyDevice = DiscoveredDevice(host: "127.0.0.1", port: 5678)
        _ = connectMockHandoff(enabledPolicyHandoff, device: enabledPolicyDevice)
        enabledPolicyHandoff.setupAutoReconnect(filter: nil)

        enabledPolicyHandoff.forceDisconnect()

        assertReconnecting(enabledPolicyHandoff.connectionPhase, device: enabledPolicyDevice)
        enabledPolicyHandoff.disableAutoReconnect()
    }

    @ButtonHeistActor
    func testDisconnectEventWithDisabledPolicyDoesNotReconnect() async {
        let handoff = TheHandoff()
        let reconnectSleeper = ManualReconnectSleeper()
        handoff.reconnectSleeper = reconnectSleeper.sleep
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        let disconnected = expectation(description: "disconnect event received")
        var connectionCount = 0
        handoff.makeConnection = { _ in
            connectionCount += 1
            let connection = MockConnection()
            connection.connectEventsOverride = [
                .connected,
                .disconnected(.serverClosed),
            ]
            return connection
        }
        handoff.onConnectionStateChanged = { state in
            if case .disconnected = state {
                disconnected.fulfill()
            }
        }

        handoff.connect(to: device)
        XCTAssertEqual(connectionCount, 1)

        await fulfillment(of: [disconnected], timeout: 5)
        await Task.yield()

        XCTAssertEqual(connectionCount, 1)
        XCTAssertEqual(reconnectSleeper.sleepCallCount, 0)
    }

    @ButtonHeistActor
    func testStaleConnectionEventsDoNotMutateNewAttempt() async {
        let handoff = TheHandoff()
        let deviceA = DiscoveredDevice(
            id: "device-a",
            name: "App#A",
            endpoint: .hostPort(host: "127.0.0.1", port: 1111)
        )
        let deviceB = DiscoveredDevice(
            id: "device-b",
            name: "App#B",
            endpoint: .hostPort(host: "127.0.0.1", port: 2222)
        )
        let connectionA = MockConnection()
        let connectionB = MockConnection()
        connectionA.connectEventsOverride = []
        connectionB.connectEventsOverride = []
        handoff.makeConnection = { device in
            switch device.id {
            case deviceA.id: return connectionA
            case deviceB.id: return connectionB
            default:
                XCTFail("Unexpected device: \(device)")
                return MockConnection()
            }
        }

        handoff.connect(to: deviceA)
        assertConnecting(handoff.connectionPhase, device: deviceA)

        handoff.connect(to: deviceB)
        assertConnecting(handoff.connectionPhase, device: deviceB)

        connectionA.onEvent?(.connected)
        assertConnecting(handoff.connectionPhase, device: deviceB)
        XCTAssertNil(handoff.connectionLifecycle.connectedDevice)

        connectionB.onEvent?(.connected)
        assertConnected(handoff.connectionPhase, device: deviceB)

        connectionA.onEvent?(.disconnected(.serverClosed))
        assertConnected(handoff.connectionPhase, device: deviceB)
    }

    @ButtonHeistActor
    func testRuntimePhaseDropsConnectionHandleWhenDisconnecting() async {
        let handoff = TheHandoff()
        let mock = connectPendingMockHandoff(handoff)

        XCTAssertNotNil(handoff.connectionLifecycle.activeConnection)

        handoff.disconnect()

        XCTAssertNil(handoff.connectionLifecycle.activeConnection)
        XCTAssertEqual(mock.disconnectCount, 1)
        assertDisconnected(handoff.connectionPhase)
        XCTAssertEqual(handoff.send(.ping, requestId: nil), .failed(.notConnected))
    }

    @ButtonHeistActor
    func testAutoReconnectDirectEndpointDoesNotRequireDiscovery() async {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0
        handoff.reconnectMaxAttempts = 2
        handoff.reconnectAttemptTimeout = 0.1
        let device = DiscoveredDevice.fromHostPort("127.0.0.1:1456")!
        let reconnected = expectation(description: "direct endpoint reconnected")

        var connectedIDs: [DiscoveryDeviceID] = []
        handoff.makeConnection = { device in
            connectedIDs.append(device.id)
            let connection = MockConnection()
            connection.connectEventsOverride = connectedIDs.count == 1
                ? [.connected, .disconnected(.serverClosed)]
                : [.connected]
            if connectedIDs.count == 2 {
                reconnected.fulfill()
            }
            return connection
        }

        handoff.setupAutoReconnect(filter: "127.0.0.1:1456")
        handoff.connect(to: device)

        await fulfillment(of: [reconnected], timeout: 5)

        XCTAssertEqual(connectedIDs, [device.id, device.id])
        assertConnected(handoff.connectionPhase, device: device)
    }

    @ButtonHeistActor
    func testAutoReconnectAttemptDoesNotCancelOwnRunner() async {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0
        handoff.reconnectMaxAttempts = 3
        handoff.reconnectAttemptTimeout = 0.1
        let device = DiscoveredDevice.fromHostPort("127.0.0.1:1457")!
        let reconnected = expectation(description: "runner survived failed reconnect attempt")

        var connectionCount = 0
        handoff.makeConnection = { _ in
            connectionCount += 1
            let connection = MockConnection()
            switch connectionCount {
            case 1:
                connection.connectEventsOverride = [.connected, .disconnected(.serverClosed)]
            case 2:
                connection.connectEventsOverride = [.disconnected(.serverClosed)]
            default:
                connection.connectEventsOverride = [.connected]
                reconnected.fulfill()
            }
            return connection
        }

        handoff.setupAutoReconnect(filter: "127.0.0.1:1457")
        handoff.connect(to: device)

        await fulfillment(of: [reconnected], timeout: 5)

        XCTAssertEqual(connectionCount, 3)
        assertConnected(handoff.connectionPhase, device: device)
    }

    @ButtonHeistActor
    func testAutoReconnectTimeoutDisconnectsAttemptBeforeRetry() async {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0
        handoff.reconnectMaxAttempts = 1
        handoff.reconnectAttemptTimeout = 0
        let device = DiscoveredDevice.fromHostPort("127.0.0.1:1458")!

        var connections: [MockConnection] = []
        handoff.makeConnection = { _ in
            let connection = MockConnection()
            connections.append(connection)
            connection.connectEventsOverride = connections.count == 1
                ? [.connected, .disconnected(.serverClosed)]
                : []
            return connection
        }

        handoff.setupAutoReconnect(filter: "127.0.0.1:1458")
        handoff.connect(to: device)

        let timedOutAttemptDisconnected = await eventually(within: .seconds(1)) {
            connections.count >= 2 && connections[1].disconnectCount > 0
        }

        XCTAssertTrue(timedOutAttemptDisconnected, "Timed-out reconnect attempt must close before any later retry")
        XCTAssertFalse(handoff.connectionLifecycle.isConnected)
        guard connections.indices.contains(1) else {
            XCTFail("Expected a reconnect attempt")
            return
        }

        connections[1].onEvent?(.connected)

        XCTAssertFalse(handoff.connectionLifecycle.isConnected, "Late success from a timed-out reconnect attempt must not resurrect stale state")
        handoff.disableAutoReconnect()
    }

    @ButtonHeistActor
    func testAutoReconnectRetriesOriginalDeviceWithoutDiscoverySelection() async {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0
        handoff.reconnectMaxAttempts = 1
        handoff.reconnectAttemptTimeout = 0.1
        let originalDevice = DiscoveredDevice(
            id: "old-service",
            name: "Checkout#old",
            endpoint: .service(name: "old-service", type: "_buttonheist._tcp", domain: "local."),
            installationId: "old-installation"
        )
        let differentDeviceMatchingFilter = DiscoveredDevice(
            id: "new-service",
            name: "Checkout#new",
            endpoint: .service(name: "new-service", type: "_buttonheist._tcp", domain: "local."),
            installationId: "new-installation"
        )
        let gaveUp = expectation(description: "reconnect reports terminal failure")

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [differentDeviceMatchingFilter]
        handoff.makeDiscovery = { mockDiscovery }
        handoff.startDiscovery()

        var connectedIDs: [DiscoveryDeviceID] = []
        handoff.makeConnection = { device in
            connectedIDs.append(device.id)
            let connection = MockConnection()
            connection.connectEventsOverride = [.connected, .disconnected(.serverClosed)]
            return connection
        }
        handoff.onStatus = { message in
            if message.contains("Auto-reconnect gave up") {
                gaveUp.fulfill()
            }
        }

        handoff.setupAutoReconnect(filter: "Checkout")
        handoff.connect(to: originalDevice)

        await fulfillment(of: [gaveUp], timeout: 5)

        XCTAssertEqual(connectedIDs, [originalDevice.id, originalDevice.id])
        assertFailed(
            handoff.connectionPhase,
            failure: .connectionFailed(
                "Auto-reconnect gave up after 1 attempts to \(originalDevice.name). Retry the connection or choose a new target."
            )
        )
    }

    func testAutoReconnectRecoveryPolicyUsesFixedJitterAndNamesTerminalFailure() {
        let policy = AutoReconnectRecoveryPolicy(maxAttempts: 3, baseInterval: 2)

        let sleepDurations = (0..<100).map { _ in policy.sleepDuration() }
        XCTAssertTrue(sleepDurations.allSatisfy { 2...2.4 ~= $0 })
        XCTAssertEqual(
            policy.terminalFailureMessage(targetDisplayName: "Checkout#old"),
            "Auto-reconnect gave up after 3 attempts to Checkout#old. Retry the connection or choose a new target."
        )
    }

    // MARK: - Discovery (existing)

    @ButtonHeistActor
    func testDiscoveryDevicesComeDirectlyFromCurrentSession() async {
        let handoff = TheHandoff()
        let mockDiscovery = MockDiscovery()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        handoff.makeDiscovery = { mockDiscovery }

        handoff.startDiscovery()
        mockDiscovery.discoveredDevices = [device]

        XCTAssertEqual(handoff.discoveryLifecycle.discoveredDevices, [device])
    }

    @ButtonHeistActor
    func testStoppedDiscoveryIgnoresStaleCallbacks() async {
        let handoff = TheHandoff()
        let staleDevice = DiscoveredDevice(
            id: "stale-service",
            name: "Stale#one",
            endpoint: .service(name: "stale-service", type: "_buttonheist._tcp", domain: "local.")
        )
        let mockDiscovery = MockDiscovery()
        handoff.makeDiscovery = { mockDiscovery }

        var foundDevices: [DiscoveredDevice] = []
        handoff.onDeviceFound = { foundDevices.append($0) }

        handoff.startDiscovery()
        XCTAssertTrue(handoff.discoveryLifecycle.isDiscovering)

        handoff.stopDiscovery()
        mockDiscovery.discoveredDevices = [staleDevice]
        mockDiscovery.onEvent?(.stateChanged(isReady: true))
        mockDiscovery.onEvent?(.found(staleDevice))

        XCTAssertFalse(handoff.discoveryLifecycle.isDiscovering)
        XCTAssertEqual(handoff.discoveryLifecycle.discoveredDevices, [])
        XCTAssertEqual(foundDevices, [])
    }

    @ButtonHeistActor
    func testDiscoveryFailureClearsDevicesAndStopsSession() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(
            id: "failed-service",
            name: "Failed#one",
            endpoint: .service(name: "failed-service", type: "_buttonheist._tcp", domain: "local.")
        )
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [device]
        handoff.makeDiscovery = { mockDiscovery }

        handoff.startDiscovery()
        XCTAssertTrue(handoff.discoveryLifecycle.isDiscovering)
        XCTAssertEqual(handoff.discoveryLifecycle.discoveredDevices, [device])

        mockDiscovery.onEvent?(.failed(.noDeviceFound))

        XCTAssertFalse(handoff.discoveryLifecycle.isDiscovering)
        XCTAssertEqual(handoff.discoveryLifecycle.discoveredDevices, [])
        XCTAssertFalse(handoff.discoveryLifecycle.hasDiscoverySession)
        XCTAssertEqual(mockDiscovery.stopCount, 1)
    }

    @ButtonHeistActor
    func testReplacedDiscoveryIgnoresCallbacksFromPreviousSession() async {
        let handoff = TheHandoff()
        let staleDevice = DiscoveredDevice(
            id: "stale-service",
            name: "Stale#one",
            endpoint: .service(name: "stale-service", type: "_buttonheist._tcp", domain: "local.")
        )
        let currentDevice = DiscoveredDevice(
            id: "current-service",
            name: "Current#one",
            endpoint: .service(name: "current-service", type: "_buttonheist._tcp", domain: "local.")
        )
        let staleDiscovery = MockDiscovery()
        let currentDiscovery = MockDiscovery()
        currentDiscovery.discoveredDevices = [currentDevice]
        var discoveries = [staleDiscovery, currentDiscovery]
        handoff.makeDiscovery = { discoveries.removeFirst() }

        var foundDevices: [DiscoveredDevice] = []
        handoff.onDeviceFound = { foundDevices.append($0) }

        handoff.startDiscovery()
        handoff.stopDiscovery()
        handoff.startDiscovery()
        staleDiscovery.discoveredDevices = [staleDevice]
        staleDiscovery.onEvent?(.stateChanged(isReady: false))
        staleDiscovery.onEvent?(.found(staleDevice))

        XCTAssertTrue(handoff.discoveryLifecycle.isDiscovering)
        XCTAssertEqual(handoff.discoveryLifecycle.discoveredDevices, [currentDevice])
        XCTAssertEqual(foundDevices, [currentDevice])
    }

    @ButtonHeistActor
    func testDeviceDiscoveryStartTwiceDoesNotReplaceActiveBrowser() async {
        let browser = FakeDiscoveryBrowser()
        let discovery = DeviceDiscovery(
            reachabilityValidationInterval: 60,
            makeBrowser: { browser }
        )

        discovery.start()
        discovery.start()

        XCTAssertEqual(browser.startCount, 1)
        XCTAssertEqual(browser.cancelCount, 0)
    }

    @ButtonHeistActor
    func testDeviceDiscoveryDeliversEventsAtBufferCapacity() async {
        let browser = FakeDiscoveryBrowser()
        let discovery = DeviceDiscovery(
            reachabilityValidationInterval: 60,
            makeBrowser: { browser }
        )
        var deliveredStateCount = 0
        var failures: [HandoffConnectionError] = []
        let capacityDelivered = HandoffTestSignal()
        discovery.onEvent = { event in
            switch event {
            case .stateChanged:
                deliveredStateCount += 1
                if deliveredStateCount == DeviceDiscoveryEventStream.bufferLimit {
                    capacityDelivered.signal()
                }
            case .failed(let failure):
                failures.append(failure)
            case .found, .lost:
                break
            }
        }

        discovery.start()
        for _ in 0..<DeviceDiscoveryEventStream.bufferLimit {
            browser.emit(.waiting)
        }
        await capacityDelivered.wait()

        XCTAssertEqual(deliveredStateCount, DeviceDiscoveryEventStream.bufferLimit)
        XCTAssertEqual(failures, [])
        XCTAssertEqual(browser.cancelCount, 0)
        discovery.stop()
    }

    @ButtonHeistActor
    func testDeviceDiscoveryOverflowInvalidatesBufferedEventsAndFailsOnce() async {
        let browser = FakeDiscoveryBrowser()
        let discovery = DeviceDiscovery(
            reachabilityValidationInterval: 60,
            makeBrowser: { browser }
        )
        var deliveredStateCount = 0
        var failures: [HandoffConnectionError] = []
        let terminalDelivered = HandoffTestSignal()
        discovery.onEvent = { event in
            switch event {
            case .stateChanged:
                deliveredStateCount += 1
            case .failed(let failure):
                failures.append(failure)
                terminalDelivered.signal()
            case .found, .lost:
                break
            }
        }

        discovery.start()
        for _ in 0...DeviceDiscoveryEventStream.bufferLimit {
            browser.emit(.waiting)
        }
        for _ in 0..<DeviceDiscoveryEventStream.bufferLimit {
            browser.emit(.ready)
        }

        XCTAssertEqual(deliveredStateCount, 0)
        XCTAssertEqual(browser.cancelCount, 1)

        await terminalDelivered.wait()

        XCTAssertEqual(deliveredStateCount, 0)
        XCTAssertEqual(failures, [
            .discoveryBacklogOverflow(capacity: DeviceDiscoveryEventStream.bufferLimit),
        ])
        XCTAssertEqual(discovery.discoveredDevices, [])
        XCTAssertEqual(browser.cancelCount, 1)
    }

    @ButtonHeistActor
    func testDeviceDiscoveryTerminalFailureClearsAndFails() async {
        let browser = FakeDiscoveryBrowser()
        let discovery = DeviceDiscovery(
            reachabilityValidationInterval: 60,
            makeBrowser: { browser }
        )
        var states: [Bool] = []
        var failures: [HandoffConnectionError] = []
        let terminalDelivered = HandoffTestSignal()
        discovery.onEvent = { event in
            switch event {
            case .stateChanged(let isReady):
                states.append(isReady)
            case .failed(let failure):
                failures.append(failure)
                terminalDelivered.signal()
            case .found, .lost:
                break
            }
        }

        discovery.start()
        browser.emit(.ready)
        browser.emit(.failed("boom"))
        await terminalDelivered.wait()

        XCTAssertEqual(states, [true])
        XCTAssertEqual(failures, [.connectionFailed("Bonjour discovery failed: boom")])
        XCTAssertEqual(discovery.discoveredDevices, [])
        XCTAssertEqual(browser.cancelCount, 1)
    }

    @ButtonHeistActor
    func testDeviceDiscoveryIgnoresStaleCallbacksAfterOverflowAndRestart() async {
        let firstBrowser = FakeDiscoveryBrowser()
        let secondBrowser = FakeDiscoveryBrowser()
        var browsers = [firstBrowser, secondBrowser]
        let discovery = DeviceDiscovery(
            reachabilityValidationInterval: 60,
            makeBrowser: { browsers.removeFirst() }
        )
        var readyStateCount = 0
        var failures: [HandoffConnectionError] = []
        let overflowDelivered = HandoffTestSignal()
        let currentReadyDelivered = HandoffTestSignal()
        discovery.onEvent = { event in
            switch event {
            case .stateChanged(let isReady):
                if isReady {
                    readyStateCount += 1
                    currentReadyDelivered.signal()
                }
            case .failed(let failure):
                failures.append(failure)
                overflowDelivered.signal()
            case .found, .lost:
                break
            }
        }

        discovery.start()
        for _ in 0...DeviceDiscoveryEventStream.bufferLimit {
            firstBrowser.emit(.waiting)
        }
        await overflowDelivered.wait()

        discovery.start()
        firstBrowser.emit(.ready)
        secondBrowser.emit(.ready)
        await currentReadyDelivered.wait()

        XCTAssertEqual(firstBrowser.cancelCount, 1)
        XCTAssertEqual(secondBrowser.startCount, 1)
        XCTAssertEqual(secondBrowser.cancelCount, 0)
        XCTAssertEqual(readyStateCount, 1)
        XCTAssertEqual(failures, [
            .discoveryBacklogOverflow(capacity: DeviceDiscoveryEventStream.bufferLimit),
        ])
        discovery.stop()
    }

    @ButtonHeistActor
    func testDiscoverReachableDevicesPreservesExistingDiscoverySession() async {
        let reachableDevice = DiscoveredDevice(
            id: "reachable-device",
            name: "ReachableApp#live",
            endpoint: .hostPort(host: "::1", port: 1)
        )
        let handoff = TheHandoff()
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [reachableDevice]
        handoff.makeDiscovery = { mockDiscovery }

        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { device in
            let connection = MockConnection()
            connection.emitTransportReadyOnConnect = true
            if device.id == reachableDevice.id {
                connection.responseScript = { message in
                    switch message {
                    case .status:
                        return .status(StatusPayload(
                            identity: StatusIdentity(
                                appName: "ReachableApp",
                                bundleIdentifier: "com.test.reachable",
                                appBuild: "1",
                                deviceName: "Simulator",
                                systemVersion: "18.5",
                                buttonHeistVersion: "5.0.0"
                            ),
                            session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                        ))
                    default:
                        XCTFail("Unexpected probe message: \(message)")
                        return .error(ServerError(kind: .general, message: "unexpected"))
                    }
                }
            }
            return connection
        }
        defer { makeReachabilityConnection = previousFactory }

        handoff.startDiscovery()
        XCTAssertTrue(handoff.discoveryLifecycle.isDiscovering)
        XCTAssertEqual(handoff.discoveryLifecycle.discoveredDevices, [reachableDevice])

        let devices = await handoff.discoverReachableDevices(timeout: 0.3)

        XCTAssertEqual(devices, [reachableDevice])
        XCTAssertTrue(handoff.discoveryLifecycle.isDiscovering)
        XCTAssertEqual(handoff.discoveryLifecycle.discoveredDevices, [reachableDevice])
        XCTAssertEqual(mockDiscovery.startCount, 1)
        XCTAssertEqual(mockDiscovery.stopCount, 0)
    }

    @ButtonHeistActor
    func testConnectWithDiscoveryDefaultSelectsSingleDiscoveredDevice() async throws {
        let discoveredDevice = DiscoveredDevice(
            id: "reachable-device",
            name: "AccessibilityTestApp#live",
            endpoint: .hostPort(host: "::1", port: 2)
        )

        let handoff = TheHandoff()
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [discoveredDevice]
        handoff.makeDiscovery = { mockDiscovery }

        var connectedDeviceID: DiscoveryDeviceID?
        handoff.makeConnection = { device in
            connectedDeviceID = device.id
            let connection = MockConnection()
            connection.serverInfo = ServerInfo(
                appName: "AccessibilityTestApp",
                bundleIdentifier: "com.buttonheist.testapp",
                deviceName: "iPhone 16 Pro",
                systemVersion: "26.1",
                screenWidth: 402,
                screenHeight: 874,
                instanceId: "accessibility-session",
                instanceIdentifier: "accessibility",
                listeningPort: 49152,
                tlsActive: true
            )
            return connection
        }

        try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)

        XCTAssertEqual(connectedDeviceID, discoveredDevice.id)
        XCTAssertEqual(handoff.connectionLifecycle.connectedDevice, discoveredDevice)
        XCTAssertTrue(handoff.connectionLifecycle.isConnected)
    }

    @ButtonHeistActor
    func testConnectWithDiscoveryDoesNotProbeReachabilityBeforeOpeningConnection() async throws {
        let device = DiscoveredDevice(
            id: "single-device",
            name: "AccessibilityTestApp#single",
            endpoint: .hostPort(host: "::1", port: 3)
        )

        let handoff = TheHandoff()
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [device]
        handoff.makeDiscovery = { mockDiscovery }

        handoff.makeConnection = { _ in
            let connection = MockConnection()
            connection.serverInfo = ServerInfo(
                appName: "AccessibilityTestApp",
                bundleIdentifier: "com.buttonheist.testapp",
                deviceName: "iPhone 16 Pro",
                systemVersion: "26.1",
                screenWidth: 402,
                screenHeight: 874,
                instanceId: "accessibility-session",
                instanceIdentifier: "accessibility",
                listeningPort: 49152,
                tlsActive: true
            )
            return connection
        }

        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { _ in
            XCTFail("connectWithDiscovery target resolution should not probe reachability")
            return MockConnection()
        }
        defer { makeReachabilityConnection = previousFactory }

        try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)

        XCTAssertEqual(handoff.connectionLifecycle.connectedDevice, device)
        XCTAssertTrue(handoff.connectionLifecycle.isConnected)
    }

    @ButtonHeistActor
    func testConnectWithDiscoveryWithoutFilterThrowsWhenMultipleDiscoveredDevicesExist() async throws {
        let firstDevice = DiscoveredDevice(
            id: "first-device",
            name: "AccessibilityTestApp#first",
            endpoint: .hostPort(host: "::1", port: 4)
        )
        let secondDevice = DiscoveredDevice(
            id: "second-device",
            name: "AccessibilityTestApp#second",
            endpoint: .hostPort(host: "::1", port: 5)
        )

        let handoff = TheHandoff()
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [firstDevice, secondDevice]
        handoff.makeDiscovery = { mockDiscovery }

        do {
            try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)
            XCTFail("Expected ambiguousDeviceTarget to be thrown")
        } catch let error as HandoffConnectionError {
            guard case .ambiguousDeviceTarget(let filter, let matches) = error else {
                return XCTFail("Expected ambiguousDeviceTarget, got \(error)")
            }
            XCTAssertEqual(filter, "(none)")
            XCTAssertEqual(matches, [firstDevice.name, secondDevice.name])
        }
    }

    @ButtonHeistActor
    func testConnectWithDiscoveryFailureReplacesExistingSession() async throws {
        let existingDevice = DiscoveredDevice(
            id: "existing-device",
            name: "AccessibilityTestApp#existing",
            endpoint: .hostPort(host: "::1", port: 6)
        )
        let firstDevice = DiscoveredDevice(
            id: "replacement-first",
            name: "AccessibilityTestApp#first",
            endpoint: .hostPort(host: "::1", port: 7)
        )
        let secondDevice = DiscoveredDevice(
            id: "replacement-second",
            name: "AccessibilityTestApp#second",
            endpoint: .hostPort(host: "::1", port: 8)
        )

        let handoff = TheHandoff()
        let existingConnection = MockConnection()
        handoff.makeConnection = { _ in existingConnection }

        var disconnectReasons: [DisconnectReason] = []
        handoff.onConnectionStateChanged = { _ in
            if case .disconnected(let reason) = handoff.connectionLifecycle.diagnosticFailure {
                disconnectReasons.append(reason)
            }
        }

        handoff.connect(to: existingDevice)
        assertConnected(handoff.connectionPhase, device: existingDevice)
        XCTAssertTrue(existingConnection.isConnected)

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [firstDevice, secondDevice]
        handoff.makeDiscovery = { mockDiscovery }
        handoff.makeConnection = { _ in
            XCTFail("Discovery selection failed; no replacement connection should be opened")
            return MockConnection()
        }

        do {
            try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)
            XCTFail("Expected ambiguousDeviceTarget to be thrown")
        } catch let error as HandoffConnectionError {
            guard case .ambiguousDeviceTarget(let filter, let matches) = error else {
                return XCTFail("Expected ambiguousDeviceTarget, got \(error)")
            }
            XCTAssertEqual(filter, "(none)")
            XCTAssertEqual(matches, [firstDevice.name, secondDevice.name])
        }

        XCTAssertFalse(existingConnection.isConnected)
        XCTAssertEqual(disconnectReasons, [.localDisconnect])
        assertDisconnected(handoff.connectionPhase)
        XCTAssertEqual(
            handoff.connectionLifecycle.diagnosticFailure,
            .ambiguousDeviceTarget(filter: "(none)", matches: [firstDevice.name, secondDevice.name])
        )
    }

    @ButtonHeistActor
    func testConnectWithDiscoverySuccessReplacesExistingSession() async throws {
        let existingDevice = DiscoveredDevice(
            id: "existing-device",
            name: "AccessibilityTestApp#existing",
            endpoint: .hostPort(host: "::1", port: 9)
        )
        let replacementDevice = DiscoveredDevice(
            id: "replacement-device",
            name: "AccessibilityTestApp#replacement",
            endpoint: .hostPort(host: "::1", port: 10)
        )

        let handoff = TheHandoff()
        let existingConnection = MockConnection()
        let replacementConnection = MockConnection()
        handoff.makeConnection = { device in
            switch device.id {
            case existingDevice.id:
                return existingConnection
            case replacementDevice.id:
                return replacementConnection
            default:
                XCTFail("Unexpected connection device: \(device)")
                return MockConnection()
            }
        }

        var disconnectReasons: [DisconnectReason] = []
        handoff.onConnectionStateChanged = { _ in
            if case .disconnected(let reason) = handoff.connectionLifecycle.diagnosticFailure {
                disconnectReasons.append(reason)
            }
        }

        handoff.connect(to: existingDevice)
        assertConnected(handoff.connectionPhase, device: existingDevice)
        XCTAssertTrue(existingConnection.isConnected)

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [replacementDevice]
        handoff.makeDiscovery = { mockDiscovery }

        try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)

        XCTAssertFalse(existingConnection.isConnected)
        XCTAssertTrue(replacementConnection.isConnected)
        XCTAssertEqual(disconnectReasons, [.localDisconnect])
        assertConnected(handoff.connectionPhase, device: replacementDevice)
        XCTAssertNil(handoff.connectionLifecycle.diagnosticFailure)
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

    @ButtonHeistActor
    private static func makeReachableTransportConnection() -> MockConnection {
        let connection = MockConnection()
        connection.emitTransportReadyOnConnect = true
        return connection
    }
}

@ButtonHeistActor
private final class HandoffTestSignal {
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
