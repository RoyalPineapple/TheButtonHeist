import XCTest
import Network
import TheGoods
@testable import Wheelman

/// Tests for session locking behavior over real TCP connections.
/// Validates that clients correctly handle sessionLocked messages and send forceSession.
final class SessionLockTests: XCTestCase {

    private var server: SimpleSocketServer!
    // Hold DeviceConnection references to prevent deallocation during async tests
    @MainActor private var deviceConnection: DeviceConnection?

    override func setUp() {
        super.setUp()
        server = SimpleSocketServer()
    }

    override func tearDown() {
        server.stop()
        server = nil
        Task { @MainActor in
            self.deviceConnection?.disconnect()
            self.deviceConnection = nil
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func startServer() throws -> UInt16 {
        try server.start(port: 0, bindToLoopback: true)
    }

    // MARK: - Tests

    func testSessionLockedDisconnectsClient() async throws {
        let port = try startServer()

        let clientConnected = expectation(description: "client connected")
        let clientDisconnected = expectation(description: "client disconnected")
        clientDisconnected.assertForOverFulfill = false

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            let payload = SessionLockedPayload(message: "Session held by another driver", activeConnections: 1)
            let msg = ServerMessage.sessionLocked(payload)
            if let data = try? JSONEncoder().encode(msg) {
                self.server.send(data, to: clientId)
            }
        }

        server.onClientDisconnected = { _ in
            clientDisconnected.fulfill()
        }

        // Use DeviceConnection so the sessionLocked handler fires and disconnects
        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let device = DiscoveredDevice(id: "test", name: "test", endpoint: endpoint)
        await MainActor.run {
            let conn = DeviceConnection(device: device, token: "test-token")
            self.deviceConnection = conn
            conn.connect()
        }

        await fulfillment(of: [clientConnected], timeout: 5.0)
        // DeviceConnection.handleMessage for .sessionLocked calls disconnect(), triggering server disconnect
        await fulfillment(of: [clientDisconnected], timeout: 5.0)
    }

    func testForceSessionSentInAuthPayload() async throws {
        let port = try startServer()

        let clientConnected = expectation(description: "client connected")
        let forceSessionReceived = expectation(description: "forceSession received")

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            let msg = ServerMessage.authRequired
            if let data = try? JSONEncoder().encode(msg) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { _, data, _ in
            guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data),
                  case .authenticate(let payload) = message else {
                XCTFail("Expected authenticate message")
                return
            }
            XCTAssertEqual(payload.forceSession, true)
            forceSessionReceived.fulfill()
        }

        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let device = DiscoveredDevice(id: "test", name: "test", endpoint: endpoint)
        await MainActor.run {
            let conn = DeviceConnection(device: device, token: "test-token", forceSession: true)
            self.deviceConnection = conn
            conn.connect()
        }

        await fulfillment(of: [clientConnected], timeout: 5.0)
        await fulfillment(of: [forceSessionReceived], timeout: 5.0)
    }

    func testNormalAuthDoesNotSendForceSession() async throws {
        let port = try startServer()

        let clientConnected = expectation(description: "client connected")
        let authReceived = expectation(description: "auth received")

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            let msg = ServerMessage.authRequired
            if let data = try? JSONEncoder().encode(msg) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { _, data, _ in
            guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data),
                  case .authenticate(let payload) = message else {
                XCTFail("Expected authenticate message")
                return
            }
            XCTAssertNil(payload.forceSession)
            authReceived.fulfill()
        }

        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let device = DiscoveredDevice(id: "test", name: "test", endpoint: endpoint)
        await MainActor.run {
            let conn = DeviceConnection(device: device, token: "test-token")
            self.deviceConnection = conn
            conn.connect()
        }

        await fulfillment(of: [clientConnected], timeout: 5.0)
        await fulfillment(of: [authReceived], timeout: 5.0)
    }

    func testSessionLockedCallbackFires() async throws {
        let port = try startServer()

        let clientConnected = expectation(description: "client connected")
        let sessionLockedFired = expectation(description: "sessionLocked callback")

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            let payload = SessionLockedPayload(message: "Another driver active", activeConnections: 3)
            let msg = ServerMessage.sessionLocked(payload)
            if let data = try? JSONEncoder().encode(msg) {
                self.server.send(data, to: clientId)
            }
        }

        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let device = DiscoveredDevice(id: "test", name: "test", endpoint: endpoint)
        await MainActor.run {
            let conn = DeviceConnection(device: device, token: "test-token")
            conn.onSessionLocked = { payload in
                XCTAssertEqual(payload.message, "Another driver active")
                XCTAssertEqual(payload.activeConnections, 3)
                sessionLockedFired.fulfill()
            }
            self.deviceConnection = conn
            conn.connect()
        }

        await fulfillment(of: [clientConnected], timeout: 5.0)
        await fulfillment(of: [sessionLockedFired], timeout: 5.0)
    }
}
