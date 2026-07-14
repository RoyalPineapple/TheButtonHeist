import XCTest
import Network
import ButtonHeistSupport
import os

@testable import TheInsideJob

final class SimpleSocketServerDeliveryTests: XCTestCase {
    func testRemoveClientNotifiesExactlyOnceAfterRegistryRemoval() async {
        let disconnectedClientIds = OSAllocatedUnfairLock<[Int]>(initialState: [])
        let server = SimpleSocketServer()
        await server.setCallbacksForTesting(SocketServerCallbacks(
            onClientDisconnected: { clientId in
                disconnectedClientIds.withLock { $0.append(clientId) }
            }
        ))
        let clientId = await server.insertClientForTesting(connection: makeConnection())

        await server.removeClient(clientId)
        await server.removeClient(clientId)

        let clientPhase = await server.clientPhaseForTesting(clientId)
        XCTAssertNil(clientPhase)
        XCTAssertEqual(disconnectedClientIds.withLock { $0 }, [clientId])
    }

    func testSendSuccessWaitsForContentProcessedCompletion() async {
        let server = SimpleSocketServer()
        let gate = SendCompletionGate()
        await server.setSendContentForTesting { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                Task { await gate.capture(handler) }
            }
        }
        let clientId = await server.insertClientForTesting(connection: makeConnection())

        let sendTask = Task {
            await server.send(Data("ok".utf8), to: clientId)
        }
        await gate.waitUntilCaptured()

        let sendingPhase = await server.clientPhaseForTesting(clientId)
        XCTAssertEqual(sendingPhase, .sending(SocketSendBuffer(pendingBytes: 3)))

        await gate.complete(nil)

        let outcome = await sendTask.value
        let connectedPhase = await server.clientPhaseForTesting(clientId)
        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(connectedPhase, .connected(SocketSendBuffer()))
        await server.removeClient(clientId)
    }

    func testResponseHandlerWaitsForContentProcessedCompletion() async {
        let server = SimpleSocketServer()
        let gate = SendCompletionGate()
        await server.setSendContentForTesting { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                Task { await gate.capture(handler) }
            }
        }
        let clientId = await server.insertClientForTesting(connection: makeConnection())
        let responder = await server.responseHandlerForTesting(clientId: clientId)

        let sendTask = Task {
            await responder(Data("reply".utf8))
        }
        await gate.waitUntilCaptured()

        let sendingPhase = await server.clientPhaseForTesting(clientId)
        XCTAssertEqual(sendingPhase, .sending(SocketSendBuffer(pendingBytes: 6)))

        await gate.complete(nil)

        let outcome = await sendTask.value
        let connectedPhase = await server.clientPhaseForTesting(clientId)
        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(connectedPhase, .connected(SocketSendBuffer()))
        await server.removeClient(clientId)
    }

    func testSendFailureReturnsNetworkTransportFailureAndRemovesClient() async {
        let server = SimpleSocketServer()
        let gate = SendCompletionGate()
        await server.setSendContentForTesting { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                Task { await gate.capture(handler) }
            }
        }
        let clientId = await server.insertClientForTesting(connection: makeConnection())

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
        let clientPhase = await server.clientPhaseForTesting(clientId)
        XCTAssertNil(clientPhase)
    }

    func testDisconnectDuringSendReturnsClientNotFound() async {
        let server = SimpleSocketServer()
        let gate = SendCompletionGate()
        await server.setSendContentForTesting { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                Task { await gate.capture(handler) }
            }
        }
        let clientId = await server.insertClientForTesting(connection: makeConnection())

        let sendTask = Task {
            await server.send(Data("response".utf8), to: clientId)
        }
        await gate.waitUntilCaptured()
        await server.removeClient(clientId)
        await gate.complete(nil)

        let outcome = await sendTask.value
        let clientPhase = await server.clientPhaseForTesting(clientId)
        XCTAssertEqual(outcome, .failed(.clientNotFound(clientId)))
        XCTAssertNil(clientPhase)
    }

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: .tcp
        )
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
