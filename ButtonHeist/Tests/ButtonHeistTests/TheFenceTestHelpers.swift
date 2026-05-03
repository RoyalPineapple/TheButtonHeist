import XCTest
import Network
@testable import ButtonHeist
import TheScore

// Shared fixtures and helpers for TheFence test classes. Keeps tests focused
// on behavior rather than repeating the connected-fence construction dance.

enum TheFenceFixtures {
    static let testDevice = DiscoveredDevice(
        id: "mock-device",
        name: "MockApp#test",
        endpoint: NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1),
        certFingerprint: "sha256:mock"
    )

    static let testServerInfo = ServerInfo(
        protocolVersion: "5.0",
        appName: "MockApp",
        bundleIdentifier: "com.test.mock",
        deviceName: "MockDevice",
        systemVersion: "18.0",
        screenWidth: 393,
        screenHeight: 852
    )
}

@ButtonHeistActor
func makeConnectedFence() -> (TheFence, MockConnection) {
    let mockConn = MockConnection()
    mockConn.serverInfo = TheFenceFixtures.testServerInfo
    mockConn.autoResponse = { message in
        switch message {
        case .requestInterface:
            return .interface(Interface(timestamp: Date(), tree: []))
        case .requestScreen:
            return .screen(ScreenPayload(pngData: "", width: 393, height: 852))
        case .stopRecording:
            return .recording(RecordingPayload(
                videoData: "", width: 390, height: 844, duration: 1,
                frameCount: 8, fps: 8, startTime: Date(), endTime: Date(),
                stopReason: .manual
            ))
        default:
            return .actionResult(ActionResult(success: true, method: .activate))
        }
    }

    let mockDisc = MockDiscovery()
    mockDisc.discoveredDevices = [TheFenceFixtures.testDevice]

    let fence = TheFence()
    fence.handoff.makeDiscovery = { mockDisc }
    fence.handoff.makeConnection = { _, _, _ in mockConn }

    makeReachabilityConnection = { _ in
        let probe = MockConnection()
        probe.emitTransportReadyOnConnect = true
        probe.autoResponse = { message in
            if case .status = message {
                return .status(StatusPayload(
                    identity: StatusIdentity(
                        appName: "Mock", bundleIdentifier: "com.test",
                        appBuild: "1", deviceName: "Mock",
                        systemVersion: "18.0", buttonHeistVersion: "0.0.1"
                    ),
                    session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                ))
            }
            return .actionResult(ActionResult(success: true, method: .activate))
        }
        return probe
    }

    return (fence, mockConn)
}
