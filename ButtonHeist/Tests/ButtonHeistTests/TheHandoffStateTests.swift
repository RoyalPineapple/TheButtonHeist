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

        assertFailed(handoff.connectionPhase, failure: .connectionFailed("something went wrong"))
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
    func testSetupAutoReconnectReplacesFilter() async {
        let handoff = TheHandoff()

        handoff.setupAutoReconnect(filter: "FirstFilter")
        handoff.setupAutoReconnect(filter: "SecondFilter")

        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: "SecondFilter", reconnectTask: nil))
    }

    @ButtonHeistActor
    func testSetupAutoReconnectCancelsStaleReconnectTaskWhenFilterChanges() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = [
            .connected,
            .disconnected(.serverClosed),
        ]
        handoff.makeConnection = { _, _, _ in mock }

        handoff.setupAutoReconnect(filter: "OldFilter")
        handoff.connect(to: device)

        guard case .enabled(filter: "OldFilter", reconnectTask: let staleTask?) = handoff.reconnectPolicy else {
            return XCTFail("Expected reconnect task for old filter")
        }

        handoff.setupAutoReconnect(filter: "NewFilter")

        XCTAssertTrue(staleTask.isCancelled)
        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: "NewFilter", reconnectTask: nil))
    }

    @ButtonHeistActor
    func testDisableAutoReconnectCancelsReconnectTaskAndClearsPolicy() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = [
            .connected,
            .disconnected(.serverClosed),
        ]
        handoff.makeConnection = { _, _, _ in mock }

        handoff.setupAutoReconnect(filter: "App")
        handoff.connect(to: device)

        guard case .enabled(filter: "App", reconnectTask: let reconnectTask?) = handoff.reconnectPolicy else {
            return XCTFail("Expected reconnect task")
        }

        handoff.disableAutoReconnect()

        XCTAssertTrue(reconnectTask.isCancelled)
        XCTAssertEqual(handoff.reconnectPolicy, .disabled)
    }

    @ButtonHeistActor
    func testReplacingAutoReconnectFilterPreventsStaleReconnect() async throws {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0.01
        let oldDevice = DiscoveredDevice(
            id: "old-device",
            name: "OldApp#one",
            endpoint: .hostPort(host: .ipv4(.loopback), port: 1111)
        )
        let newDevice = DiscoveredDevice(
            id: "new-device",
            name: "NewApp#one",
            endpoint: .hostPort(host: .ipv4(.loopback), port: 2222)
        )

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [oldDevice, newDevice]
        handoff.makeDiscovery = { mockDiscovery }
        handoff.startDiscovery()

        var connectedIDs: [String] = []
        handoff.makeConnection = { device, _, _ in
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

        handoff.setupAutoReconnect(filter: "NewApp")

        // Negative assertion: give the stale reconnect task time to fire if it
        // survived the filter replacement.
        // swiftlint:disable:next agent_test_task_sleep
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(connectedIDs, ["old-device"])
        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: "NewApp", reconnectTask: nil))
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
    func testNonRetryableDisconnectDoesNotTriggerReconnect() async throws {
        let handoff = TheHandoff()
        handoff.reconnectInterval = 0.01
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        let disconnected = expectation(description: "disconnect event received")
        var connectionCount = 0
        handoff.makeConnection = { _, _, _ in
            connectionCount += 1
            let connection = MockConnection()
            connection.connectEventsOverride = [
                .disconnected(.missingFingerprint),
            ]
            return connection
        }
        handoff.onDisconnected = { _ in
            disconnected.fulfill()
        }

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [device]
        handoff.makeDiscovery = { mockDiscovery }
        handoff.startDiscovery()
        handoff.setupAutoReconnect(filter: nil)

        handoff.connect(to: device)
        await fulfillment(of: [disconnected], timeout: 5)

        XCTAssertEqual(connectionCount, 1)
        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: nil, reconnectTask: nil))
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

        // Give the reconnect loop time to fire if it were going to (it shouldn't).
        // Asserts a *negative* — needs wall-clock elapsed time, not a signal to wait on.
        // swiftlint:disable:next agent_test_task_sleep
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(connectionCount, 1)
        XCTAssertEqual(handoff.reconnectPolicy, .disabled)
    }

    @ButtonHeistActor
    func testStaleConnectionEventsDoNotMutateNewAttempt() async {
        let handoff = TheHandoff()
        let deviceA = DiscoveredDevice(
            id: "device-a",
            name: "App#A",
            endpoint: .hostPort(host: .ipv4(.loopback), port: 1111)
        )
        let deviceB = DiscoveredDevice(
            id: "device-b",
            name: "App#B",
            endpoint: .hostPort(host: .ipv4(.loopback), port: 2222)
        )
        let connectionA = MockConnection()
        let connectionB = MockConnection()
        connectionA.connectEventsOverride = []
        connectionB.connectEventsOverride = []
        handoff.makeConnection = { device, _, _ in
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
        XCTAssertNil(handoff.connectedDevice)

        connectionB.onEvent?(.connected)
        assertConnected(handoff.connectionPhase, device: deviceB)

        connectionA.onEvent?(.disconnected(.serverClosed))
        assertConnected(handoff.connectionPhase, device: deviceB)
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

    @ButtonHeistActor
    func testConnectWithDiscoveryFailureReplacesExistingSession() async throws {
        let existingDevice = DiscoveredDevice(
            id: "existing-device",
            name: "AccessibilityTestApp#existing",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 6),
            certFingerprint: "sha256:existing"
        )
        let firstDevice = DiscoveredDevice(
            id: "replacement-first",
            name: "AccessibilityTestApp#first",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 7),
            certFingerprint: "sha256:first"
        )
        let secondDevice = DiscoveredDevice(
            id: "replacement-second",
            name: "AccessibilityTestApp#second",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 8),
            certFingerprint: "sha256:second"
        )

        let handoff = TheHandoff()
        let existingConnection = MockConnection()
        handoff.makeConnection = { _, _, _ in existingConnection }

        var disconnectReasons: [DisconnectReason] = []
        handoff.onDisconnected = { reason in
            disconnectReasons.append(reason)
        }

        handoff.connect(to: existingDevice)
        assertConnected(handoff.connectionPhase, device: existingDevice)
        XCTAssertTrue(existingConnection.isConnected)

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [firstDevice, secondDevice]
        handoff.makeDiscovery = { mockDiscovery }
        handoff.makeConnection = { _, _, _ in
            XCTFail("Discovery selection failed; no replacement connection should be opened")
            return MockConnection()
        }

        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { _ in Self.makeReachableStatusConnection() }
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

        XCTAssertFalse(existingConnection.isConnected)
        XCTAssertEqual(disconnectReasons, [.localDisconnect])
        assertDisconnected(handoff.connectionPhase)
        XCTAssertEqual(
            handoff.connectionDiagnosticFailure,
            .noMatchingDevice(filter: "(none)", available: [firstDevice.name, secondDevice.name])
        )
    }

    @ButtonHeistActor
    func testConnectWithDiscoverySuccessReplacesExistingSession() async throws {
        let existingDevice = DiscoveredDevice(
            id: "existing-device",
            name: "AccessibilityTestApp#existing",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 9),
            certFingerprint: "sha256:existing"
        )
        let replacementDevice = DiscoveredDevice(
            id: "replacement-device",
            name: "AccessibilityTestApp#replacement",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 10),
            certFingerprint: "sha256:replacement"
        )

        let handoff = TheHandoff()
        let existingConnection = MockConnection()
        let replacementConnection = MockConnection()
        handoff.makeConnection = { device, _, _ in
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
        handoff.onDisconnected = { reason in
            disconnectReasons.append(reason)
        }

        handoff.connect(to: existingDevice)
        assertConnected(handoff.connectionPhase, device: existingDevice)
        XCTAssertTrue(existingConnection.isConnected)

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [replacementDevice]
        handoff.makeDiscovery = { mockDiscovery }

        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { _ in Self.makeReachableStatusConnection() }
        defer { makeReachabilityConnection = previousFactory }

        try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)

        XCTAssertFalse(existingConnection.isConnected)
        XCTAssertTrue(replacementConnection.isConnected)
        XCTAssertEqual(disconnectReasons, [.localDisconnect])
        assertConnected(handoff.connectionPhase, device: replacementDevice)
        XCTAssertNil(handoff.connectionDiagnosticFailure)
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
        assertFailed(handoff.connectionPhase, failure: .connectionFailed("boom"))

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
    func testCancellingOneWaiterDoesNotCancelSiblingWaiter() async throws {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _, _, _ in mock }

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
        handoff.makeConnection = { _, _, _ in mock }

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
        } catch let error as TheHandoff.ConnectionError {
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

    @ButtonHeistActor
    func testTerminalConnectionFailureResolvesAllLiveWaitersForAttempt() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _, _, _ in mock }

        handoff.connect(to: device)

        let firstWaitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }
        let secondWaitTask = Task { @ButtonHeistActor in
            try await handoff.waitForConnectionResult(timeout: 30)
        }
        await Task.yield()

        mock.onEvent?(.disconnected(.missingFingerprint))

        for waitTask in [firstWaitTask, secondWaitTask] {
            do {
                try await waitTask.value
                XCTFail("Expected disconnect failure")
            } catch let error as TheHandoff.ConnectionError {
                XCTAssertEqual(error, .disconnected(.missingFingerprint))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testTerminalAttemptDeliversRequestScopedError() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _, _, _ in mock }

        var receivedError: ServerError?
        var receivedRequestID: String?
        handoff.onRequestError = { error, requestID in
            receivedError = error
            receivedRequestID = requestID
        }

        handoff.connect(to: device)
        mock.onEvent?(.connected)
        mock.onEvent?(.message(
            .error(ServerError(kind: .general, message: "connection failed")),
            requestId: nil,
            backgroundAccessibilityDelta: nil,
            accessibilityTrace: nil
        ))
        assertFailed(handoff.connectionPhase, failure: .connectionFailed("connection failed"))

        mock.onEvent?(.message(
            .error(ServerError(kind: .general, message: "request failed")),
            requestId: "request-1",
            backgroundAccessibilityDelta: nil,
            accessibilityTrace: nil
        ))

        XCTAssertEqual(receivedError?.message, "request failed")
        XCTAssertEqual(receivedRequestID, "request-1")
        assertFailed(handoff.connectionPhase, failure: .connectionFailed("connection failed"))
    }

    @ButtonHeistActor
    func testTerminalAttemptIgnoresStateMutatingRequestScopedMessages() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = []
        handoff.makeConnection = { _, _, _ in mock }

        var connectedInfo: ServerInfo?
        handoff.onConnected = { info in
            connectedInfo = info
        }

        handoff.connect(to: device)
        mock.onEvent?(.connected)
        mock.onEvent?(.message(
            .error(ServerError(kind: .general, message: "connection failed")),
            requestId: nil,
            backgroundAccessibilityDelta: nil,
            accessibilityTrace: nil
        ))

        mock.onEvent?(.message(
            .info(TheFenceFixtures.testServerInfo),
            requestId: "request-1",
            backgroundAccessibilityDelta: nil,
            accessibilityTrace: nil
        ))

        XCTAssertNil(connectedInfo)
        XCTAssertNil(handoff.serverInfo)
        assertFailed(handoff.connectionPhase, failure: .connectionFailed("connection failed"))
    }

    @ButtonHeistActor
    func testWaitForConnectionResultPreservesDisconnectCause() async {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mock = MockConnection()
        mock.connectEventsOverride = [
            .disconnected(.missingFingerprint),
        ]
        handoff.makeConnection = { _, _, _ in mock }

        handoff.connect(to: device)

        do {
            try await handoff.waitForConnectionResult(timeout: 30)
            XCTFail("Expected disconnect failure")
        } catch let error as TheHandoff.ConnectionError {
            guard case .disconnected(let reason) = error else {
                return XCTFail("Expected .disconnected, got \(error)")
            }
            XCTAssertEqual(reason, .missingFingerprint)
            XCTAssertEqual(error.failureCode, "tls.missing_fingerprint")
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
        handoff.makeConnection = { _, _, _ in mock }
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
        handoff.makeConnection = { _, _, _ in mock }

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

        // Drive into .failed (server error) — this is a terminal phase.
        handoff.handleServerMessage(
            .error(ServerError(kind: .general, message: "boom")),
            requestId: nil
        )
        assertFailed(handoff.connectionPhase, failure: .connectionFailed("boom"))

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
        } catch is TheHandoff.ConnectionError {
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
        handoff.makeConnection = { _, _, _ in mock }

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
        XCTAssertTrue(handoff.isConnected)
    }

    @ButtonHeistActor
    private static func makeReachableStatusConnection() -> MockConnection {
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
}
