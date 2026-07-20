import XCTest
import Network
import ButtonHeistSupport
import os

@testable import TheInsideJob

final class SimpleSocketServerDeliveryTests: XCTestCase {
    func testRemoveClientNotifiesExactlyOnceAfterRegistryRemoval() async throws {
        let disconnectedClientIds = OSAllocatedUnfairLock<[Int]>(initialState: [])
        let server = deliveryServer(callbacks: SocketServerCallbacks(
            onClientDisconnected: { clientId in disconnectedClientIds.withLock { $0.append(clientId) } }
        ))
        try await startForDeliveryTesting(server)
        let clientId = try await insertClientForDeliveryTesting(into: server)

        await server.removeClient(clientId)
        await server.removeClient(clientId)

        let pendingSendBytes = await server.clientPendingSendBytesForTesting(clientId)
        XCTAssertNil(pendingSendBytes)
        XCTAssertEqual(disconnectedClientIds.withLock { $0 }, [clientId])
        await server.stop()
    }

    func testSendSuccessWaitsForContentProcessedCompletion() async throws {
        let gate = SendCompletionGate()
        let server = deliveryServer { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                Task { await gate.capture(handler) }
            }
        }
        try await startForDeliveryTesting(server)
        let clientId = try await insertClientForDeliveryTesting(into: server)

        let sendTask = Task {
            await server.send(Data("ok".utf8), to: clientId)
        }
        await gate.waitUntilCaptured()

        let pendingSendBytes = await server.clientPendingSendBytesForTesting(clientId)
        XCTAssertEqual(pendingSendBytes, 3)

        await gate.complete(nil)

        let outcome = await sendTask.value
        let completedPendingSendBytes = await server.clientPendingSendBytesForTesting(clientId)
        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(completedPendingSendBytes, 0)
        await server.stop()
    }

    func testRejectedClientErrorUsesReservedSendBeforeDisconnecting() async throws {
        let sendGate = SendCompletionGate()
        let disconnections = AsyncStream.makeStream(of: Int.self)
        let server = deliveryServer(
            callbacks: SocketServerCallbacks(
                onClientDisconnected: { disconnections.continuation.yield($0) }
            )
        ) { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                Task { await sendGate.capture(handler) }
            }
        }
        try await startForDeliveryTesting(server)
        let clientId = try await insertClientForDeliveryTesting(into: server)
        var disconnectIterator = disconnections.stream.makeAsyncIterator()

        await server.rejectClientWithServerError(
            clientId,
            kind: .validationError,
            message: "Invalid request"
        )
        await sendGate.waitUntilCaptured()

        let pendingSendBytes = await server.clientPendingSendBytesForTesting(clientId)
        let clientCount = await server.clientCountForTesting
        XCTAssertGreaterThan(try XCTUnwrap(pendingSendBytes), 0)
        XCTAssertEqual(clientCount, 1)

        await sendGate.complete(nil)

        let disconnectedClientId = await disconnectIterator.next()
        let completedPendingSendBytes = await server.clientPendingSendBytesForTesting(clientId)
        XCTAssertEqual(disconnectedClientId, clientId)
        XCTAssertNil(completedPendingSendBytes)
        await server.stop()
    }

    func testSendFailureReturnsNetworkTransportFailureAndRemovesClient() async throws {
        let gate = SendCompletionGate()
        let server = deliveryServer { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                Task { await gate.capture(handler) }
            }
        }
        try await startForDeliveryTesting(server)
        let clientId = try await insertClientForDeliveryTesting(into: server)

        let sendTask = Task {
            await server.send(Data("response".utf8), to: clientId)
        }
        await gate.waitUntilCaptured()
        await gate.complete(.posix(.ECONNRESET))

        guard case .failed(.transportFailed(let failedClientId, let diagnostic)) = await sendTask.value else {
            return XCTFail("Expected transport failure from send completion")
        }
        XCTAssertEqual(failedClientId, clientId)
        XCTAssertEqual(diagnostic.reason, .posix(code: Int(POSIXErrorCode.ECONNRESET.rawValue)))
        let pendingSendBytes = await server.clientPendingSendBytesForTesting(clientId)
        XCTAssertNil(pendingSendBytes)
        await server.stop()
    }

    func testDisconnectDuringSendReturnsClientNotFound() async throws {
        let gate = SendCompletionGate()
        let server = deliveryServer { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                Task { await gate.capture(handler) }
            }
        }
        try await startForDeliveryTesting(server)
        let clientId = try await insertClientForDeliveryTesting(into: server)

        let sendTask = Task {
            await server.send(Data("response".utf8), to: clientId)
        }
        await gate.waitUntilCaptured()
        await server.removeClient(clientId)
        await gate.complete(nil)

        let outcome = await sendTask.value
        let pendingSendBytes = await server.clientPendingSendBytesForTesting(clientId)
        XCTAssertEqual(outcome, .failed(.clientNotFound(clientId)))
        XCTAssertNil(pendingSendBytes)
        await server.stop()
    }

    func testSendCompletionAfterStopIsRejectedByListenerGeneration() async throws {
        let gate = SendCompletionGate()
        let server = deliveryServer { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                Task { await gate.capture(handler) }
            }
        }
        try await startForDeliveryTesting(server)
        let clientId = try await insertClientForDeliveryTesting(into: server)

        let sendTask = Task {
            await server.send(Data("response".utf8), to: clientId)
        }
        await gate.waitUntilCaptured()
        await server.stop()
        await gate.complete(nil)

        let outcome = await sendTask.value
        XCTAssertEqual(outcome, .failed(.transportUnavailable))
    }

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: .tcp
        )
    }

    private func startForDeliveryTesting(_ server: SimpleSocketServer) async throws {
        _ = try await server.startPlaintext()
    }

    private func deliveryServer(
        callbacks: SocketServerCallbacks = SocketServerCallbacks(),
        sendContent: @escaping SocketSendContent = { connection, content, completion in
            connection.send(content: content, completion: completion)
        }
    ) -> SimpleSocketServer {
        let listeners = TestSocketListenerFactory(port: 49_152)
        return SimpleSocketServer(
            callbacks: callbacks,
            dependencies: SimpleSocketServer.Dependencies(
                sendContent: sendContent,
                listenerFactory: listeners.listenerFactory
            )
        )
    }

    private func insertClientForDeliveryTesting(into server: SimpleSocketServer) async throws -> Int {
        let clientId = await server.insertClientForTesting(connection: makeConnection())
        return try XCTUnwrap(clientId)
    }
}

private actor SendCompletionGate {
    private var handler: (@Sendable (NWError?) -> Void)?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func capture(_ handler: @escaping @Sendable (NWError?) -> Void) {
        self.handler = handler
        let waiters = self.waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilCaptured() async {
        guard handler == nil else { return }
        await withCheckedContinuation { continuation in
            if handler != nil {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func complete(_ error: NWError?) {
        handler?(error)
    }
}
