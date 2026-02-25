import XCTest
import Network
import TheGoods
@testable import Wheelman

/// Tests for auth failure handling over real TCP connections.
/// Validates that authFailed fires correctly and isn't swallowed by the subsequent disconnect.
final class AuthFailureTests: XCTestCase {

    private var server: SimpleSocketServer!
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
            let authReq = ServerMessage.authRequired
            if let data = try? JSONEncoder().encode(authReq) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { _, _, respond in
            // Reject with authFailed
            let failed = ServerMessage.authFailed("Invalid token. Retry without a token to request a fresh session.")
            if let data = try? JSONEncoder().encode(failed) {
                respond(data)
            }
        }

        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let device = DiscoveredDevice(id: "test", name: "test", endpoint: endpoint)
        await MainActor.run {
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
            let authReq = ServerMessage.authRequired
            if let data = try? JSONEncoder().encode(authReq) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { _, _, respond in
            let failed = ServerMessage.authFailed("Invalid token. Retry without a token to request a fresh session.")
            if let data = try? JSONEncoder().encode(failed) {
                respond(data)
            }
        }

        var callOrder: [String] = []
        let endpoint = NWEndpoint.hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let device = DiscoveredDevice(id: "test", name: "test", endpoint: endpoint)
        await MainActor.run {
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
        await MainActor.run {
            XCTAssertEqual(callOrder.first, "authFailed", "authFailed should fire before disconnected")
        }
    }
}
