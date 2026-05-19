// Integration tests for SimpleSocketServer state machine transitions.
// Uses real NWListener on loopback and real NWConnection — requires TCP networking.

import XCTest
import Network
import os
import TheScore
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
        } catch let error as SimpleSocketServer.ServerError {
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

    func testSendToMissingClientFailsTyped() async throws {
        let outcome = await server.send(Data("late-response".utf8), to: 404)

        guard case .failed(.clientNotFound(404)) = outcome else {
            return XCTFail("Expected clientNotFound failure, got \(outcome)")
        }
    }

    func testAsyncSendCompletionFailureEmitsTypedCallback() async throws {
        let capturedClientId = OSAllocatedUnfairLock<Int?>(initialState: nil)
        let capturedFailure = OSAllocatedUnfairLock<ServerSendFailure?>(initialState: nil)
        let clientConnected = expectation(description: "client connected")
        let sendFailed = expectation(description: "send failed")

        let callbacks = SimpleSocketServer.Callbacks(
            onClientConnected: { clientId, _ in
                capturedClientId.withLock { $0 = clientId }
                clientConnected.fulfill()
            },
            onSendFailed: { _, failure in
                capturedFailure.withLock { $0 = failure }
                sendFailed.fulfill()
            }
        )
        let port = try await server.startAsync(port: 0, bindToLoopback: true, callbacks: callbacks)
        await server.setSendContentForTesting { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                handler(.posix(.ECONNRESET))
            }
        }

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

        let outcome = await server.send(Data("response".utf8), to: clientId)

        XCTAssertEqual(outcome, .enqueued)
        await fulfillment(of: [sendFailed], timeout: 5.0)
        guard case .transportFailed(let failedClientId, let message) = capturedFailure.withLock({ $0 }) else {
            connection.cancel()
            return XCTFail("Expected transportFailed callback, got \(String(describing: capturedFailure.withLock { $0 }))")
        }
        XCTAssertEqual(failedClientId, clientId)
        XCTAssertFalse(message.isEmpty)
        connection.cancel()
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

    func testScopeRejectionSendsServerErrorBeforeDisconnect() async throws {
        await server.stop()
        server = SimpleSocketServer(allowedScopes: [.usb])

        let port = try await server.startAsync(port: 0, bindToLoopback: true)
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

        await fulfillment(of: [clientReady], timeout: 5.0)

        let response = try await receiveData(from: connection)
        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: response)
        guard case .error(let error) = envelope.message else {
            connection.cancel()
            return XCTFail("Expected server error before scope rejection teardown, got \(envelope.message)")
        }
        XCTAssertEqual(error.kind, .general)
        XCTAssertEqual(error.message, "Connection rejected: simulator connections are not allowed by this server.")

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

    // MARK: - Helpers

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
