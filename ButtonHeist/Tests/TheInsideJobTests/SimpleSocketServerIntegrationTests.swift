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

    // MARK: - Connection admission

    func testConnectionAdmissionRejectsReadyAfterEarlyCancel() {
        let admission = ConnectionAdmission()

        XCTAssertEqual(admission.recordCancellation(), .noRegisteredClient)
        XCTAssertEqual(admission.recordReady(), .ignore)
    }

    func testConnectionAdmissionRequestsCleanupWhenCancelArrivesDuringAcceptance() {
        let admission = ConnectionAdmission()

        XCTAssertEqual(admission.recordReady(), .accept)
        XCTAssertEqual(admission.recordCancellation(), .noRegisteredClient)
        XCTAssertEqual(
            admission.recordAcceptance(.registered(clientId: 7)),
            .removeRegisteredClient(7)
        )
        XCTAssertEqual(admission.recordCancellation(), .noRegisteredClient)
    }

    func testConnectionAdmissionReturnsAcceptedClientForLateCancel() {
        let admission = ConnectionAdmission()

        XCTAssertEqual(admission.recordReady(), .accept)
        XCTAssertEqual(
            admission.recordAcceptance(.registered(clientId: 7)),
            .keepRegisteredClient
        )
        XCTAssertEqual(admission.recordCancellation(), .removeRegisteredClient(7))
        XCTAssertEqual(admission.recordCancellation(), .noRegisteredClient)
    }

    func testConnectionAdmissionRejectedReadyIsTerminal() {
        let admission = ConnectionAdmission()

        XCTAssertEqual(admission.recordReady(), .accept)
        XCTAssertEqual(admission.recordAcceptance(.rejected), .noRegisteredClient)
        XCTAssertEqual(admission.recordCancellation(), .noRegisteredClient)
        XCTAssertEqual(admission.recordReady(), .ignore)
    }

    func testConnectionAdmissionIgnoresDuplicateReadyDuringAcceptance() {
        let admission = ConnectionAdmission()

        XCTAssertEqual(admission.recordReady(), .accept)
        XCTAssertEqual(admission.recordReady(), .ignore)
        XCTAssertEqual(
            admission.recordAcceptance(.registered(clientId: 7)),
            .keepRegisteredClient
        )
        XCTAssertEqual(admission.recordCancellation(), .removeRegisteredClient(7))
    }

    func testConnectionAdmissionIgnoresAcceptanceBeforeReady() {
        let admission = ConnectionAdmission()

        XCTAssertEqual(
            admission.recordAcceptance(.registered(clientId: 7)),
            .noRegisteredClient
        )
        XCTAssertEqual(admission.recordReady(), .accept)
        XCTAssertEqual(
            admission.recordAcceptance(.registered(clientId: 8)),
            .keepRegisteredClient
        )
        XCTAssertEqual(admission.recordCancellation(), .removeRegisteredClient(8))
    }

    // MARK: - ServerPhase transitions

    func testStartTransitionsToListening() async throws {
        let port = try await server.startPlaintextForTests(port: 0, bindToLoopback: true)
        XCTAssertGreaterThan(port, 0)
        XCTAssertEqual(server.listeningPort, port)
    }

    func testDoubleStartThrowsAlreadyRunning() async throws {
        _ = try await server.startPlaintextForTests(port: 0, bindToLoopback: true)

        do {
            _ = try await server.startPlaintextForTests(port: 0, bindToLoopback: true)
            XCTFail("Expected alreadyRunning error on double start")
        } catch let error as SimpleSocketServer.ServerError {
            XCTAssertEqual(error, .alreadyRunning)
        }
    }

    func testStopFromListeningResetsPort() async throws {
        _ = try await server.startPlaintextForTests(port: 0, bindToLoopback: true)
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

        let callbacks = SocketServerCallbacks(
            onClientConnected: { clientId, _ in
                capturedClientId.withLock { $0 = clientId }
                clientConnected.fulfill()
            },
            onSendFailed: { _, failure in
                capturedFailure.withLock { $0 = failure }
                sendFailed.fulfill()
            }
        )
        let port = try await server.startPlaintextForTests(port: 0, bindToLoopback: true, callbacks: callbacks)
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
        let firstPort = try await server.startPlaintextForTests(port: 0, bindToLoopback: true)
        XCTAssertGreaterThan(firstPort, 0)

        await server.stop()

        let secondPort = try await server.startPlaintextForTests(port: 0, bindToLoopback: true)
        XCTAssertGreaterThan(secondPort, 0)
    }

    // MARK: - Client lifecycle

    func testNewClientRoutesFramedDataToRawDataCallback() async throws {
        let capturedClientId = OSAllocatedUnfairLock<Int?>(initialState: nil)
        let capturedData = OSAllocatedUnfairLock<Data?>(initialState: nil)
        let clientConnected = expectation(description: "client connected")
        let dataReceived = expectation(description: "data received")

        let callbacks = SocketServerCallbacks(
            onClientConnected: { clientId, _ in
                capturedClientId.withLock { $0 = clientId }
                clientConnected.fulfill()
            },
            onDataReceived: { _, data, _ in
                capturedData.withLock { $0 = data }
                dataReceived.fulfill()
            }
        )
        let port = try await server.startPlaintextForTests(port: 0, bindToLoopback: true, callbacks: callbacks)

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
        connection.send(content: Data("raw-frame\n".utf8), completion: .contentProcessed { error in
            XCTAssertNil(error)
        })

        await fulfillment(of: [dataReceived], timeout: 5.0)
        XCTAssertEqual(capturedData.withLock { $0 }, Data("raw-frame".utf8))
        XCTAssertGreaterThan(clientId, 0)

        connection.cancel()
    }

    func testTransportDeliversFramesBeyondMessageRateLimit() async throws {
        let capturedFrames = OSAllocatedUnfairLock<[String]>(initialState: [])
        let clientConnected = expectation(description: "client connected")
        let dataReceived = expectation(description: "data received")
        dataReceived.expectedFulfillmentCount = MessageRateLimiter.defaultMaxMessagesPerSecond + 1

        let callbacks = SocketServerCallbacks(
            onClientConnected: { _, _ in
                clientConnected.fulfill()
            },
            onDataReceived: { _, data, _ in
                let frame = String(data: data, encoding: .utf8) ?? ""
                capturedFrames.withLock { $0.append(frame) }
                dataReceived.fulfill()
            }
        )
        let port = try await server.startPlaintextForTests(port: 0, bindToLoopback: true, callbacks: callbacks)

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

        let payload = (0...MessageRateLimiter.defaultMaxMessagesPerSecond)
            .map { "raw-frame-\($0)\n" }
            .joined()
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { error in
            XCTAssertNil(error)
        })

        await fulfillment(of: [dataReceived], timeout: 5.0)
        XCTAssertEqual(capturedFrames.withLock { $0.count }, MessageRateLimiter.defaultMaxMessagesPerSecond + 1)
        XCTAssertEqual(capturedFrames.withLock { $0.first }, "raw-frame-0")
        XCTAssertEqual(capturedFrames.withLock { $0.last }, "raw-frame-\(MessageRateLimiter.defaultMaxMessagesPerSecond)")

        connection.cancel()
    }

    func testDisconnectRemovesClient() async throws {
        let capturedClientId = OSAllocatedUnfairLock<Int?>(initialState: nil)
        let clientConnected = expectation(description: "client connected")
        let clientDisconnected = expectation(description: "client disconnected")

        let callbacks = SocketServerCallbacks(
            onClientConnected: { clientId, _ in
                capturedClientId.withLock { $0 = clientId }
                clientConnected.fulfill()
            },
            onClientDisconnected: { _ in
                clientDisconnected.fulfill()
            }
        )
        let port = try await server.startPlaintextForTests(port: 0, bindToLoopback: true, callbacks: callbacks)

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
        await server.removeClient(clientId)

        await fulfillment(of: [clientDisconnected], timeout: 5.0)

        connection.cancel()
    }

    func testScopeRejectionSendsServerErrorBeforeDisconnect() async throws {
        await server.stop()
        server = SimpleSocketServer(allowedScopes: [.usb])
        let clientConnected = expectation(description: "scope-rejected client must not be accepted")
        clientConnected.isInverted = true
        let callbacks = SocketServerCallbacks(
            onClientConnected: { _, _ in clientConnected.fulfill() }
        )

        let port = try await server.startPlaintextForTests(port: 0, bindToLoopback: true, callbacks: callbacks)
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
        await fulfillment(of: [clientConnected], timeout: 0.2)

        connection.cancel()
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
