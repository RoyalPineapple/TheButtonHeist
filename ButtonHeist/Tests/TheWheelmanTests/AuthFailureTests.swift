import XCTest
import Network
import TheScore
@testable import TheWheelman

/// Tests for auth failure handling over real TCP connections.
/// Validates that authFailed fires correctly and isn't swallowed by the subsequent disconnect.
final class AuthFailureTests: XCTestCase {

    private var server: SimpleSocketServer!
    @ButtonHeistActor private var deviceConnection: DeviceConnection?

    override func setUp() {
        super.setUp()
        server = SimpleSocketServer()
    }

    override func tearDown() {
        server.stop()
        server = nil
        Task { @ButtonHeistActor in
            self.deviceConnection?.disconnect()
            self.deviceConnection = nil
        }
        super.tearDown()
    }

    private func startServer() throws -> UInt16 {
        try server.start(port: 0, bindToLoopback: true)
    }

    // MARK: - Tests

    func testAuthFailedCallbackFires() async throws {
        let port = try startServer()

        let clientConnected = expectation(description: "client connected")
        let authFailedFired = expectation(description: "authFailed callback")

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            // Send authRequired then authFailed (simulating wrong token rejection)
            if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .authRequired)) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { _, _, respond in
            // Reject with authFailed
            if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .authFailed("Invalid token. Retry without a token to request a fresh session."))) {
                respond(data)
            }
        }

        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let device = DiscoveredDevice(id: "test", name: "test", endpoint: endpoint)
        await ButtonHeistActor.run {
            let conn = DeviceConnection(device: device, token: "wrong-token")
            conn.onAuthFailed = { reason in
                XCTAssertTrue(reason.contains("Invalid token"))
                authFailedFired.fulfill()
            }
            self.deviceConnection = conn
            conn.connect()
        }

        await fulfillment(of: [clientConnected], timeout: 5.0)
        await fulfillment(of: [authFailedFired], timeout: 5.0)
    }

    func testAuthFailedFiresBeforeDisconnected() async throws {
        let port = try startServer()

        let clientConnected = expectation(description: "client connected")
        let authFailedFired = expectation(description: "authFailed callback")
        let disconnectedFired = expectation(description: "disconnected callback")
        disconnectedFired.assertForOverFulfill = false

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .authRequired)) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { _, _, respond in
            if let data = try? JSONEncoder().encode(ResponseEnvelope(message: .authFailed("Invalid token. Retry without a token to request a fresh session."))) {
                respond(data)
            }
        }

        var callOrder: [String] = []
        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let device = DiscoveredDevice(id: "test", name: "test", endpoint: endpoint)
        await ButtonHeistActor.run {
            let conn = DeviceConnection(device: device, token: "wrong-token")
            conn.onAuthFailed = { _ in
                callOrder.append("authFailed")
                authFailedFired.fulfill()
            }
            conn.onDisconnected = { _ in
                callOrder.append("disconnected")
                disconnectedFired.fulfill()
            }
            self.deviceConnection = conn
            conn.connect()
        }

        await fulfillment(of: [clientConnected], timeout: 5.0)
        await fulfillment(of: [authFailedFired], timeout: 5.0)
        await fulfillment(of: [disconnectedFired], timeout: 5.0)

        // Verify authFailed fires before disconnected
        await ButtonHeistActor.run {
            XCTAssertEqual(callOrder.first, "authFailed", "authFailed should fire before disconnected")
        }
    }
}
