// Integration tests for SimpleSocketServer state machine transitions.
// Uses real NWListener on loopback and real NWConnection — requires TCP networking.

import XCTest
import Network
import os
@testable import TheInsideJob

final class SimpleSocketServerIntegrationTests: XCTestCase {

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

    // MARK: - ServerPhase transitions

    func testStartTransitionsToListening() async throws {
        let port = try await server.startAsync(port: 0, bindToLoopback: true)
        XCTAssertGreaterThan(port, 0)
        XCTAssertEqual(server.listeningPort, port)
    }

    func testDoubleStartThrowsAlreadyRunning() async throws {
        _ = try await server.startAsync(port: 0, bindToLoopback: true)

        do {
            _ = try await server.startAsync(port: 0, bindToLoopback: true)
            XCTFail("Expected alreadyRunning error on double start")
        } catch let error as SimpleSocketServer.SocketServerError {
            XCTAssertEqual(error, .alreadyRunning)
        }
    }

    func testStopFromListeningResetsPort() async throws {
        _ = try await server.startAsync(port: 0, bindToLoopback: true)
        XCTAssertGreaterThan(server.listeningPort, 0)

        await server.stop()
        XCTAssertEqual(server.listeningPort, 0)
    }

    func testStopFromStoppedIsNoOp() async throws {
        await server.stop()
        XCTAssertEqual(server.listeningPort, 0)
    }

    func testCanRestartAfterStop() async throws {
        let firstPort = try await server.startAsync(port: 0, bindToLoopback: true)
        XCTAssertGreaterThan(firstPort, 0)

        await server.stop()

        let secondPort = try await server.startAsync(port: 0, bindToLoopback: true)
        XCTAssertGreaterThan(secondPort, 0)
    }

    // MARK: - ClientPhase transitions

    func testNewClientStartsUnauthenticated() async throws {
        let capturedClientId = OSAllocatedUnfairLock<Int?>(initialState: nil)
        let clientConnected = expectation(description: "client connected")

        let callbacks = SimpleSocketServer.Callbacks(
            onClientConnected: { clientId, _ in
                capturedClientId.withLock { $0 = clientId }
                clientConnected.fulfill()
            }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, callbacks: callbacks)

        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let clientReady = expectation(description: "client ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state { clientReady.fulfill() }
        }
        connection.start(queue: .global())

        await fulfillment(of: [clientReady, clientConnected], timeout: 5.0)

        let clientId = try XCTUnwrap(capturedClientId.withLock { $0 })
        let isAuthenticated = await server.isAuthenticated(clientId)
        XCTAssertFalse(isAuthenticated, "New client should be unauthenticated")

        connection.cancel()
    }

    func testMarkAuthenticatedTransitionsClient() async throws {
        let capturedClientId = OSAllocatedUnfairLock<Int?>(initialState: nil)
        let clientConnected = expectation(description: "client connected")

        let callbacks = SimpleSocketServer.Callbacks(
            onClientConnected: { clientId, _ in
                capturedClientId.withLock { $0 = clientId }
                clientConnected.fulfill()
            }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, callbacks: callbacks)

        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let clientReady = expectation(description: "client ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state { clientReady.fulfill() }
        }
        connection.start(queue: .global())

        await fulfillment(of: [clientReady, clientConnected], timeout: 5.0)

        let clientId = try XCTUnwrap(capturedClientId.withLock { $0 })
        await server.markAuthenticated(clientId)

        let isAuthenticated = await server.isAuthenticated(clientId)
        XCTAssertTrue(isAuthenticated, "Client should be authenticated after markAuthenticated")

        connection.cancel()
    }

    func testMarkAuthenticatedOnAlreadyAuthenticatedIsNoOp() async throws {
        let capturedClientId = OSAllocatedUnfairLock<Int?>(initialState: nil)
        let clientConnected = expectation(description: "client connected")

        let callbacks = SimpleSocketServer.Callbacks(
            onClientConnected: { clientId, _ in
                capturedClientId.withLock { $0 = clientId }
                clientConnected.fulfill()
            }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, callbacks: callbacks)

        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let clientReady = expectation(description: "client ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state { clientReady.fulfill() }
        }
        connection.start(queue: .global())

        await fulfillment(of: [clientReady, clientConnected], timeout: 5.0)

        let clientId = try XCTUnwrap(capturedClientId.withLock { $0 })
        await server.markAuthenticated(clientId)
        await server.markAuthenticated(clientId)

        let isAuthenticated = await server.isAuthenticated(clientId)
        XCTAssertTrue(isAuthenticated)

        connection.cancel()
    }

    func testDisconnectRemovesClient() async throws {
        let capturedClientId = OSAllocatedUnfairLock<Int?>(initialState: nil)
        let clientConnected = expectation(description: "client connected")
        let clientDisconnected = expectation(description: "client disconnected")

        let callbacks = SimpleSocketServer.Callbacks(
            onClientConnected: { clientId, _ in
                capturedClientId.withLock { $0 = clientId }
                clientConnected.fulfill()
            },
            onClientDisconnected: { _ in
                clientDisconnected.fulfill()
            }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, callbacks: callbacks)

        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let clientReady = expectation(description: "client ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state { clientReady.fulfill() }
        }
        connection.start(queue: .global())

        await fulfillment(of: [clientReady, clientConnected], timeout: 5.0)

        let clientId = try XCTUnwrap(capturedClientId.withLock { $0 })
        await server.disconnect(clientId: clientId)

        await fulfillment(of: [clientDisconnected], timeout: 5.0)

        let isAuthenticated = await server.isAuthenticated(clientId)
        XCTAssertFalse(isAuthenticated, "Disconnected client should not be authenticated")

        connection.cancel()
    }

    func testBroadcastOnlyReachesAuthenticatedClients() async throws {
        let capturedClientIds = OSAllocatedUnfairLock<[Int]>(initialState: [])
        let firstConnected = expectation(description: "first client connected")
        let secondConnected = expectation(description: "second client connected")

        let callbacks = SimpleSocketServer.Callbacks(
            onClientConnected: { clientId, _ in
                let count = capturedClientIds.withLock { ids -> Int in
                    ids.append(clientId)
                    return ids.count
                }
                if count == 1 { firstConnected.fulfill() }
                if count == 2 { secondConnected.fulfill() }
            }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, callbacks: callbacks)

        let connection1 = NWConnection(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let ready1 = expectation(description: "client 1 ready")
        connection1.stateUpdateHandler = { state in
            if case .ready = state { ready1.fulfill() }
        }
        connection1.start(queue: .global())
        await fulfillment(of: [ready1, firstConnected], timeout: 5.0)

        let connection2 = NWConnection(host: .ipv6(.loopback), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let ready2 = expectation(description: "client 2 ready")
        connection2.stateUpdateHandler = { state in
            if case .ready = state { ready2.fulfill() }
        }
        connection2.start(queue: .global())
        await fulfillment(of: [ready2, secondConnected], timeout: 5.0)

        let authenticatedClientId = capturedClientIds.withLock { $0[0] }
        await server.markAuthenticated(authenticatedClientId)

        let testMessage = Data("broadcast-test\n".utf8)
        await server.broadcastToAll(testMessage)

        let received = expectation(description: "authenticated client receives broadcast")
        connection1.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, _ in
            if let content, String(data: content, encoding: .utf8)?.contains("broadcast-test") == true {
                received.fulfill()
            }
        }
        await fulfillment(of: [received], timeout: 5.0)

        let notReceived = expectation(description: "unauthenticated client does not receive")
        notReceived.isInverted = true
        connection2.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, _ in
            if let content, String(data: content, encoding: .utf8)?.contains("broadcast-test") == true {
                notReceived.fulfill()
            }
        }
        await fulfillment(of: [notReceived], timeout: 0.5)

        connection1.cancel()
        connection2.cancel()
    }
}
