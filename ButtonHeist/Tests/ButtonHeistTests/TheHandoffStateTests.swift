import XCTest
@testable import ButtonHeist
import TheScore

final class TheHandoffStateTests: XCTestCase {

    @ButtonHeistActor
    func testInitialState() async {
        let handoff = TheHandoff()

        XCTAssertTrue(handoff.discoveredDevices.isEmpty)
        XCTAssertNil(handoff.connectedDevice)
        XCTAssertNil(handoff.serverInfo)
        XCTAssertNil(handoff.currentInterface)
        XCTAssertFalse(handoff.isDiscovering)
        assertDisconnected(handoff.connectionPhase)
        XCTAssertEqual(handoff.reconnectPolicy, .disabled)
        XCTAssertEqual(handoff.recordingPhase, .idle)
        XCTAssertFalse(handoff.isRecording)
    }

    @ButtonHeistActor
    func testDisconnectClearsState() async {
        let handoff = TheHandoff()

        handoff.disconnect()

        XCTAssertNil(handoff.connectedDevice)
        XCTAssertNil(handoff.serverInfo)
        XCTAssertNil(handoff.currentInterface)
        assertDisconnected(handoff.connectionPhase)
        XCTAssertEqual(handoff.recordingPhase, .idle)
    }

    @ButtonHeistActor
    func testStopDiscoveryClearsFlag() async {
        let handoff = TheHandoff()

        handoff.startDiscovery()
        handoff.stopDiscovery()

        XCTAssertFalse(handoff.isDiscovering)
    }

    @ButtonHeistActor
    func testServerErrorSetsConnectionPhaseFailed() async {
        let handoff = TheHandoff()
        var receivedError: String?
        handoff.onError = { receivedError = $0 }

        handoff.handleServerMessage(.error(ServerError(kind: .general, message: "something went wrong")), requestId: nil)

        assertFailed(handoff.connectionPhase, failure: .error("something went wrong"))
        XCTAssertEqual(receivedError, "something went wrong")
    }

    @ButtonHeistActor
    func testMultipleDisconnectsSafe() async {
        let handoff = TheHandoff()

        handoff.disconnect()
        handoff.disconnect()
        handoff.disconnect()

        assertDisconnected(handoff.connectionPhase)
    }

    // MARK: - ReconnectPolicy

    @ButtonHeistActor
    func testSetupAutoReconnectSetsPolicy() async {
        let handoff = TheHandoff()

        handoff.setupAutoReconnect(filter: "MyApp")

        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: "MyApp", reconnectTask: nil))
    }

    @ButtonHeistActor
    func testSetupAutoReconnectWithNilFilter() async {
        let handoff = TheHandoff()

        handoff.setupAutoReconnect(filter: nil)

        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: nil, reconnectTask: nil))
    }

    @ButtonHeistActor
    func testSetupAutoReconnectIsIdempotent() async {
        let handoff = TheHandoff()

        handoff.setupAutoReconnect(filter: "FirstFilter")
        handoff.setupAutoReconnect(filter: "SecondFilter")

        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: "FirstFilter", reconnectTask: nil))
    }

    @ButtonHeistActor
    func testReconnectPolicyRemainsEnabledAfterDisconnect() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [device]
        handoff.makeDiscovery = { mockDiscovery }

        var connectionCount = 0
        handoff.makeConnection = { _, _, _ in
            connectionCount += 1
            let connection = MockConnection()
            connection.serverInfo = ServerInfo(
                appName: "TestApp",
                bundleIdentifier: "com.test",
                deviceName: "Simulator",
                systemVersion: "26.1",
                screenWidth: 402,
                screenHeight: 874
            )
            return connection
        }

        handoff.startDiscovery()
        handoff.setupAutoReconnect(filter: nil)
        handoff.connect(to: device)
        XCTAssertEqual(connectionCount, 1)

        // After explicit disconnect, the policy should remain enabled
        // (disconnect doesn't reset the policy — only the connection)
        handoff.disconnect()
        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: nil, reconnectTask: nil))
    }

    @ButtonHeistActor
    func testReconnectPolicyStartsDisabled() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        handoff.makeConnection = { _, _, _ in
            let connection = MockConnection()
            connection.serverInfo = ServerInfo(
                appName: "TestApp",
                bundleIdentifier: "com.test",
                deviceName: "Simulator",
                systemVersion: "26.1",
                screenWidth: 402,
                screenHeight: 874
            )
            return connection
        }

        handoff.connect(to: device)
        XCTAssertEqual(handoff.reconnectPolicy, .disabled)
    }

    // MARK: - ReconnectPolicy Trigger

    @ButtonHeistActor
    func testDisconnectEventWithEnabledPolicyTriggersReconnect() async throws {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0.01
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        let reconnected = expectation(description: "reconnect connection made")
        var connectionCount = 0
        handoff.makeConnection = { _, _, _ in
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
                    screenHeight: 874
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
    func testDisconnectEventWithDisabledPolicyDoesNotReconnect() async throws {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0.01
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        let disconnected = expectation(description: "disconnect event received")
        var connectionCount = 0
        handoff.makeConnection = { _, _, _ in
            connectionCount += 1
            let connection = MockConnection()
            connection.connectEventsOverride = [
                .connected,
                .disconnected(.serverClosed),
            ]
            return connection
        }
        handoff.onDisconnected = { _ in
            disconnected.fulfill()
        }

        handoff.connect(to: device)
        XCTAssertEqual(connectionCount, 1)

        await fulfillment(of: [disconnected], timeout: 5)

        // Give the reconnect loop time to fire if it were going to (it shouldn't)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(connectionCount, 1)
        XCTAssertEqual(handoff.reconnectPolicy, .disabled)
    }

    // MARK: - RecordingPhase

    @ButtonHeistActor
    func testRecordingStartedSetsPhaseToRecording() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)

        handoff.handleServerMessage(.recordingStarted, requestId: nil)

        XCTAssertEqual(handoff.recordingPhase, .recording)
        XCTAssertTrue(handoff.isRecording)
    }

    @ButtonHeistActor
    func testRecordingCompletedResetsPhaseToIdle() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        handoff.handleServerMessage(.recordingStarted, requestId: nil)

        handoff.handleServerMessage(.recording(RecordingPayload(
            videoData: "",
            width: 100,
            height: 200,
            duration: 1.0,
            frameCount: 10,
            fps: 10,
            startTime: Date(),
            endTime: Date(),
            stopReason: .manual,
            interactionLog: nil
        )), requestId: nil)

        XCTAssertEqual(handoff.recordingPhase, .idle)
        XCTAssertFalse(handoff.isRecording)
    }

    @ButtonHeistActor
    func testRecordingErrorResetsPhaseToIdle() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        handoff.handleServerMessage(.recordingStarted, requestId: nil)

        handoff.handleServerMessage(
            .error(ServerError(kind: .recording, message: "disk full")),
            requestId: nil
        )

        XCTAssertEqual(handoff.recordingPhase, .idle)
        XCTAssertFalse(handoff.isRecording)
    }

    @ButtonHeistActor
    func testDisconnectResetsRecordingPhase() async {
        let handoff = TheHandoff()
        connectMockHandoff(handoff)
        handoff.handleServerMessage(.recordingStarted, requestId: nil)
        XCTAssertEqual(handoff.recordingPhase, .recording)

        handoff.disconnect()

        XCTAssertEqual(handoff.recordingPhase, .idle)
    }

    // MARK: - Discovery (existing)

    @ButtonHeistActor
    func testDiscoverReachableDevicesPreservesExistingDiscoverySession() async {
        let reachableDevice = DiscoveredDevice(
            id: "reachable-device",
            name: "ReachableApp#live",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:reachable"
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
                connection.autoResponse = { message in
                    switch message {
                    case .status:
                        return .status(StatusPayload(
                            identity: StatusIdentity(
                                appName: "ReachableApp",
                                bundleIdentifier: "com.test.reachable",
                                appBuild: "1",
                                deviceName: "Simulator",
                                systemVersion: "18.5",
                                buttonHeistVersion: "5.0"
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
        XCTAssertTrue(handoff.isDiscovering)
        XCTAssertEqual(handoff.discoveredDevices, [reachableDevice])

        let devices = await handoff.discoverReachableDevices(timeout: 0.3)

        XCTAssertEqual(devices, [reachableDevice])
        XCTAssertTrue(handoff.isDiscovering)
        XCTAssertEqual(handoff.discoveredDevices, [reachableDevice])
        XCTAssertEqual(mockDiscovery.startCount, 1)
        XCTAssertEqual(mockDiscovery.stopCount, 0)
    }

    @ButtonHeistActor
    func testConnectWithDiscoveryIgnoresStaleDevicesWithoutFilter() async throws {
        let staleDevice = DiscoveredDevice(
            id: "stale-device",
            name: "AccessibilityTestApp#stale",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:stale"
        )
        let reachableDevice = DiscoveredDevice(
            id: "reachable-device",
            name: "AccessibilityTestApp#live",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 2),
            certFingerprint: "sha256:reachable"
        )

        let handoff = TheHandoff()
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [staleDevice, reachableDevice]
        handoff.makeDiscovery = { mockDiscovery }

        var connectedDeviceID: String?
        handoff.makeConnection = { device, _, _ in
            connectedDeviceID = device.id
            let connection = MockConnection()
            connection.serverInfo = ServerInfo(
                appName: "AccessibilityTestApp",
                bundleIdentifier: "com.buttonheist.testapp",
                deviceName: "iPhone 16 Pro",
                systemVersion: "26.1",
                screenWidth: 402,
                screenHeight: 874
            )
            return connection
        }

        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { device in
            let connection = MockConnection()
            connection.emitTransportReadyOnConnect = true
            if device.id == reachableDevice.id {
                connection.autoResponse = { message in
                    switch message {
                    case .status:
                        return .status(StatusPayload(
                            identity: StatusIdentity(
                                appName: "AccessibilityTestApp",
                                bundleIdentifier: "com.buttonheist.testapp",
                                appBuild: "1",
                                deviceName: "iPhone 16 Pro",
                                systemVersion: "26.1",
                                buttonHeistVersion: "5.0"
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

        try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)

        XCTAssertEqual(connectedDeviceID, reachableDevice.id)
        XCTAssertEqual(handoff.connectedDevice, reachableDevice)
        XCTAssertTrue(handoff.isConnected)
    }

    @ButtonHeistActor
    func testConnectWithDiscoveryReprobesDeviceThatBecomesReachableWithoutRediscovery() async throws {
        let delayedDevice = DiscoveredDevice(
            id: "delayed-device",
            name: "AccessibilityTestApp#booting",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 3),
            certFingerprint: "sha256:delayed"
        )

        let handoff = TheHandoff()
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [delayedDevice]
        handoff.makeDiscovery = { mockDiscovery }

        handoff.makeConnection = { _, _, _ in
            let connection = MockConnection()
            connection.serverInfo = ServerInfo(
                appName: "AccessibilityTestApp",
                bundleIdentifier: "com.buttonheist.testapp",
                deviceName: "iPhone 16 Pro",
                systemVersion: "26.1",
                screenWidth: 402,
                screenHeight: 874
            )
            return connection
        }

        var probeAttempts = 0
        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { device in
            let connection = MockConnection()
            if device.id == delayedDevice.id {
                if probeAttempts == 0 {
                    connection.connectEventsOverride = [
                        .transportReady,
                        .disconnected(.serverClosed),
                    ]
                } else {
                    connection.emitTransportReadyOnConnect = true
                    connection.autoResponse = { message in
                        switch message {
                        case .status:
                            return .status(StatusPayload(
                                identity: StatusIdentity(
                                    appName: "AccessibilityTestApp",
                                    bundleIdentifier: "com.buttonheist.testapp",
                                    appBuild: "1",
                                    deviceName: "iPhone 16 Pro",
                                    systemVersion: "26.1",
                                    buttonHeistVersion: "5.0"
                                ),
                                session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                            ))
                        default:
                            XCTFail("Unexpected probe message: \(message)")
                            return .error(ServerError(kind: .general, message: "unexpected"))
                        }
                    }
                }
                probeAttempts += 1
            }
            return connection
        }
        defer { makeReachabilityConnection = previousFactory }

        let start = Date()
        try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)

        XCTAssertEqual(handoff.connectedDevice, delayedDevice)
        XCTAssertTrue(handoff.isConnected)
        XCTAssertGreaterThanOrEqual(probeAttempts, 2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4.5)
    }

    @ButtonHeistActor
    func testConnectWithDiscoveryWithoutFilterThrowsWhenMultipleReachableDevicesExist() async throws {
        let firstDevice = DiscoveredDevice(
            id: "first-device",
            name: "AccessibilityTestApp#first",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 4),
            certFingerprint: "sha256:first"
        )
        let secondDevice = DiscoveredDevice(
            id: "second-device",
            name: "AccessibilityTestApp#second",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 5),
            certFingerprint: "sha256:second"
        )

        let handoff = TheHandoff()
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [firstDevice, secondDevice]
        handoff.makeDiscovery = { mockDiscovery }

        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { _ in
            let connection = MockConnection()
            connection.emitTransportReadyOnConnect = true
            connection.autoResponse = { message in
                switch message {
                case .status:
                    return .status(StatusPayload(
                        identity: StatusIdentity(
                            appName: "AccessibilityTestApp",
                            bundleIdentifier: "com.buttonheist.testapp",
                            appBuild: "1",
                            deviceName: "iPhone 16 Pro",
                            systemVersion: "26.1",
                            buttonHeistVersion: "5.0"
                        ),
                        session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                    ))
                default:
                    XCTFail("Unexpected probe message: \(message)")
                    return .error(ServerError(kind: .general, message: "unexpected"))
                }
            }
            return connection
        }
        defer { makeReachabilityConnection = previousFactory }

        do {
            try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)
            XCTFail("Expected noMatchingDevice to be thrown")
        } catch let error as TheHandoff.ConnectionError {
            guard case .noMatchingDevice(let filter, let available) = error else {
                return XCTFail("Expected noMatchingDevice, got \(error)")
            }
            XCTAssertEqual(filter, "(none)")
            XCTAssertEqual(available, [firstDevice.name, secondDevice.name])
        }
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
            screenHeight: 874
        )
        handoff.makeConnection = { _, _, _ in mock }

        handoff.connect(to: device)
        XCTAssertTrue(handoff.isConnected)

        // Already connected — should return immediately without throwing.
        try await handoff.waitForConnectionResult(timeout: 5)
    }

    @ButtonHeistActor
    func testWaitForConnectionResultThrowsWhenAlreadyFailed() async {
        let handoff = TheHandoff()
        // Drive into .failed state via a server error.
        handoff.handleServerMessage(
            .error(ServerError(kind: .general, message: "boom")),
            requestId: nil
        )
        assertFailed(handoff.connectionPhase, failure: .error("boom"))

        do {
            try await handoff.waitForConnectionResult(timeout: 5)
            XCTFail("Expected ConnectionError to be thrown")
        } catch let error as TheHandoff.ConnectionError {
            guard case .connectionFailed(let message) = error else {
                return XCTFail("Expected .connectionFailed, got \(error)")
            }
            XCTAssertEqual(message, "boom")
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
        handoff.makeConnection = { _, _, _ in mock }

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
        XCTAssertTrue(handoff.isConnected)

        try await waitTask.value
    }

    @ButtonHeistActor
    func testWaitForConnectionResultPropagatesCancellationError() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []  // Stays in .connecting until cancelled
        handoff.makeConnection = { _, _, _ in mock }

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
    func testWaitForConnectionResultResumesOnFailedTransition() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _, _, _ in mock }

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
        } catch let error as TheHandoff.ConnectionError {
            guard case .authFailed(let reason) = error else {
                return XCTFail("Expected .authFailed, got \(error)")
            }
            XCTAssertEqual(reason, "bad token")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
