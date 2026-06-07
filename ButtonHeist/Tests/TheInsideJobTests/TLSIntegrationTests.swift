import XCTest
import Network

import TheScore
@testable import TheInsideJob

/// Integration tests for token-derived Network.framework TLS-PSK transport.
final class TLSIntegrationTests: XCTestCase {

    private var server: SimpleSocketServer!

    override func setUp() {
        super.setUp()
        server = SimpleSocketServer()
    }

    override func tearDown() async throws {
        await server.stop()
        server = nil
        try await super.tearDown()
    }

    func testTLSHandshakeWithPreSharedKey() async throws {
        let token = "correct horse battery staple"
        let tlsParams = ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token)

        let connected = expectation(description: "client connected to server")
        let callbacks = SocketServerCallbacks(
            onClientConnected: { _, _ in connected.fulfill() }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, tlsParameters: tlsParams, callbacks: callbacks)
        XCTAssertGreaterThan(port, 0)

        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token)
        )

        let clientReady = expectation(description: "client TLS handshake complete")
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                clientReady.fulfill()
            }
        }
        connection.start(queue: .global())

        await fulfillment(of: [clientReady, connected], timeout: 5.0)
        connection.cancel()
    }

    func testDataExchangeOverTLSPreSharedKey() async throws {
        let token = "shared-token"
        let echoMessage = Data("hello-tls\n".utf8)
        let echoReceived = expectation(description: "server received message")

        let callbacks = SocketServerCallbacks(
            onDataReceived: { _, data, respond in
                respond(data)
                echoReceived.fulfill()
            }
        )
        let port = try await server.startAsync(
            port: 0,
            bindToLoopback: true,
            tlsParameters: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token),
            callbacks: callbacks
        )

        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token)
        )

        let clientReady = expectation(description: "client ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                clientReady.fulfill()
            }
        }
        connection.start(queue: .global())
        await fulfillment(of: [clientReady], timeout: 5.0)

        connection.send(content: echoMessage, completion: .contentProcessed { error in
            XCTAssertNil(error, "Send should succeed over TLS")
        })

        await fulfillment(of: [echoReceived], timeout: 5.0)

        let receivedData = try await receiveData(from: connection)
        let received = String(data: receivedData, encoding: .utf8) ?? ""
        XCTAssertTrue(received.contains("hello-tls"), "Should receive echoed data over TLS")

        connection.cancel()
    }

    func testWrongPreSharedKeyRejectsConnection() async throws {
        let port = try await server.startAsync(
            port: 0,
            bindToLoopback: true,
            tlsParameters: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: "server-token")
        )

        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: "client-token")
        )

        let connectionFailed = expectation(description: "connection should fail or not reach ready")
        connectionFailed.assertForOverFulfill = false
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled, .waiting:
                connectionFailed.fulfill()
            default:
                break
            }
        }
        connection.start(queue: .global())

        await fulfillment(of: [connectionFailed], timeout: 5.0)
        connection.cancel()
    }

    func testPassiveReachabilityDoesNotSendUnauthenticatedStatusOverTLS() async throws {
        let token = "probe-token"
        let clientConnected = expectation(description: "client connected")
        let unexpectedPreAuthData = expectation(description: "no unauthenticated status probe")
        unexpectedPreAuthData.isInverted = true

        let callbacks = SocketServerCallbacks(
            onClientConnected: { _, _ in
                clientConnected.fulfill()
            },
            onDataReceived: { _, _, _ in
                unexpectedPreAuthData.fulfill()
            }
        )
        let port = try await server.startAsync(
            port: 0,
            bindToLoopback: true,
            tlsParameters: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token),
            callbacks: callbacks
        )

        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: ButtonHeistTLSPreSharedKey.makeNetworkParameters(token: token)
        )

        let clientReady = expectation(description: "client ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                clientReady.fulfill()
            }
        }
        connection.start(queue: .global())
        await fulfillment(of: [clientReady, clientConnected], timeout: 5.0)
        await fulfillment(of: [unexpectedPreAuthData], timeout: 0.2)

        connection.cancel()
    }

    private func receiveData(from connection: NWConnection, timeout: TimeInterval = 5.0) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let content {
                            continuation.resume(returning: content)
                        } else {
                            continuation.resume(
                                throwing: NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])
                            )
                        }
                    }
                }
            }
            group.addTask {
                // Group-race timeout against a real network read; needs wall-clock.
                // swiftlint:disable:next agent_test_task_sleep
                try await Task.sleep(for: .seconds(timeout))
                throw NSError(domain: "test", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "receiveData timed out after \(timeout)s"
                ])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
