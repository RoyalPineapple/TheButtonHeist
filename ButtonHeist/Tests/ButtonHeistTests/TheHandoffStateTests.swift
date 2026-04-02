import XCTest
@testable import ButtonHeist
import TheScore

@ButtonHeistActor
final class TheHandoffStateTests: XCTestCase {

    func testInitialState() {
        let handoff = TheHandoff()

        XCTAssertTrue(handoff.discoveredDevices.isEmpty)
        XCTAssertNil(handoff.connectedDevice)
        XCTAssertNil(handoff.serverInfo)
        XCTAssertNil(handoff.currentInterface)
        XCTAssertFalse(handoff.isDiscovering)
        XCTAssertEqual(handoff.connectionPhase, .disconnected)
        XCTAssertEqual(handoff.reconnectPolicy, .disabled)
        XCTAssertEqual(handoff.recordingPhase, .idle)
        XCTAssertFalse(handoff.isRecording)
    }

    func testDisconnectClearsState() {
        let handoff = TheHandoff()

        handoff.disconnect()

        XCTAssertNil(handoff.connectedDevice)
        XCTAssertNil(handoff.serverInfo)
        XCTAssertNil(handoff.currentInterface)
        XCTAssertEqual(handoff.connectionPhase, .disconnected)
        XCTAssertEqual(handoff.recordingPhase, .idle)
    }

    func testStopDiscoveryClearsFlag() {
        let handoff = TheHandoff()

        handoff.startDiscovery()
        handoff.stopDiscovery()

        XCTAssertFalse(handoff.isDiscovering)
    }

    func testServerErrorSetsConnectionPhaseFailed() {
        let handoff = TheHandoff()
        var receivedError: String?
        handoff.onError = { receivedError = $0 }

        handoff.handleServerMessage(.error("something went wrong"), requestId: nil)

        XCTAssertEqual(handoff.connectionPhase, .failed(.error("something went wrong")))
        XCTAssertEqual(receivedError, "something went wrong")
    }

    func testMultipleDisconnectsSafe() {
        let handoff = TheHandoff()

        handoff.disconnect()
        handoff.disconnect()
        handoff.disconnect()

        XCTAssertEqual(handoff.connectionPhase, .disconnected)
    }

    // MARK: - ReconnectPolicy

    func testSetupAutoReconnectSetsPolicy() {
        let handoff = TheHandoff()

        handoff.setupAutoReconnect(filter: "MyApp")

        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: "MyApp"))
    }

    func testSetupAutoReconnectWithNilFilter() {
        let handoff = TheHandoff()

        handoff.setupAutoReconnect(filter: nil)

        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: nil))
    }

    func testSetupAutoReconnectIsIdempotent() {
        let handoff = TheHandoff()

        handoff.setupAutoReconnect(filter: "FirstFilter")
        handoff.setupAutoReconnect(filter: "SecondFilter")

        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: "FirstFilter"))
    }

    func testReconnectPolicyRemainsEnabledAfterDisconnect() {
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
                protocolVersion: "5.0",
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
        XCTAssertEqual(handoff.reconnectPolicy, .enabled(filter: nil))
    }

    func testReconnectPolicyStartsDisabled() {
        let handoff = TheHandoff()
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)

        handoff.makeConnection = { _, _, _ in
            let connection = MockConnection()
            connection.serverInfo = ServerInfo(
                protocolVersion: "5.0",
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
                    protocolVersion: "5.0",
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

    func testRecordingStartedSetsPhaseToRecording() {
        let handoff = TheHandoff()

        handoff.handleServerMessage(.recordingStarted, requestId: nil)

        XCTAssertEqual(handoff.recordingPhase, .recording)
        XCTAssertTrue(handoff.isRecording)
    }

    func testRecordingCompletedResetsPhaseToIdle() {
        let handoff = TheHandoff()
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

    func testRecordingErrorResetsPhaseToIdle() {
        let handoff = TheHandoff()
        handoff.handleServerMessage(.recordingStarted, requestId: nil)

        handoff.handleServerMessage(.recordingError("disk full"), requestId: nil)

        XCTAssertEqual(handoff.recordingPhase, .idle)
        XCTAssertFalse(handoff.isRecording)
    }

    func testDisconnectResetsRecordingPhase() {
        let handoff = TheHandoff()
        handoff.handleServerMessage(.recordingStarted, requestId: nil)
        XCTAssertEqual(handoff.recordingPhase, .recording)

        handoff.disconnect()

        XCTAssertEqual(handoff.recordingPhase, .idle)
    }

    // MARK: - Discovery (existing)

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
                        return .error("unexpected")
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
                protocolVersion: "5.0",
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
                        return .error("unexpected")
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
                protocolVersion: "5.0",
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
                            return .error("unexpected")
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
                    return .error("unexpected")
                }
            }
            return connection
        }
        defer { makeReachabilityConnection = previousFactory }

        do {
            try await handoff.connectWithDiscovery(filter: nil, timeout: 0.5)
            XCTFail("Expected noMatchingDevice to be thrown")
        } catch let error as FenceError {
            guard case .noMatchingDevice(let filter, let available) = error else {
                return XCTFail("Expected noMatchingDevice, got \(error)")
            }
            XCTAssertEqual(filter, "(none)")
            XCTAssertEqual(available, [firstDevice.name, secondDevice.name])
        }
    }
}
