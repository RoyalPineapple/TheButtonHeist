import XCTest
import Network
import ButtonHeistSupport

@testable import TheInsideJob

final class SimpleSocketServerDeliveryTests: XCTestCase {
    func testSendSuccessWaitsForContentProcessedCompletion() async {
        let server = SimpleSocketServer()
        let gate = SendCompletionGate()
        await server.setSendContentForTesting { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                gate.capture(handler)
            }
        }
        let clientId = await server.insertClientForTesting(connection: makeConnection())

        let sendTask = Task {
            await server.send(Data("ok".utf8), to: clientId)
        }
        await gate.waitUntilCaptured()

        XCTAssertEqual(
            await server.clientPhaseForTesting(clientId),
            .sending(SocketSendBuffer(pendingBytes: 3))
        )

        gate.complete(nil)

        XCTAssertEqual(await sendTask.value, .enqueued)
        XCTAssertEqual(
            await server.clientPhaseForTesting(clientId),
            .connected(SocketSendBuffer())
        )
        await server.removeClient(clientId)
    }

    func testResponseHandlerDeliverWaitsForContentProcessedCompletion() async {
        let server = SimpleSocketServer()
        let gate = SendCompletionGate()
        await server.setSendContentForTesting { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                gate.capture(handler)
            }
        }
        let clientId = await server.insertClientForTesting(connection: makeConnection())
        let responder = await server.responseHandlerForTesting(clientId: clientId)

        let sendTask = Task {
            await responder.deliver(Data("reply".utf8))
        }
        await gate.waitUntilCaptured()

        XCTAssertEqual(
            await server.clientPhaseForTesting(clientId),
            .sending(SocketSendBuffer(pendingBytes: 6))
        )

        gate.complete(nil)

        XCTAssertEqual(await sendTask.value, .enqueued)
        XCTAssertEqual(
            await server.clientPhaseForTesting(clientId),
            .connected(SocketSendBuffer())
        )
        await server.removeClient(clientId)
    }

    func testSendFailureReturnsNetworkTransportFailureAndRemovesClient() async {
        let server = SimpleSocketServer()
        let gate = SendCompletionGate()
        await server.setSendContentForTesting { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                gate.capture(handler)
            }
        }
        let clientId = await server.insertClientForTesting(connection: makeConnection())

        let sendTask = Task {
            await server.send(Data("response".utf8), to: clientId)
        }
        await gate.waitUntilCaptured()
        gate.complete(.posix(.ECONNRESET))

        guard case .failed(.transportFailed(let failedClientId, let diagnostic)) = await sendTask.value else {
            return XCTFail("Expected transport failure from send completion")
        }
        XCTAssertEqual(failedClientId, clientId)
        XCTAssertEqual(diagnostic.reason, .posix(code: Int(POSIXErrorCode.ECONNRESET.rawValue)))
        XCTAssertNil(await server.clientPhaseForTesting(clientId))
    }

    func testDisconnectDuringSendReturnsClientNotFound() async {
        let server = SimpleSocketServer()
        let gate = SendCompletionGate()
        await server.setSendContentForTesting { _, _, completion in
            if case .contentProcessed(let handler) = completion {
                gate.capture(handler)
            }
        }
        let clientId = await server.insertClientForTesting(connection: makeConnection())

        let sendTask = Task {
            await server.send(Data("response".utf8), to: clientId)
        }
        await gate.waitUntilCaptured()
        await server.removeClient(clientId)
        gate.complete(nil)

        XCTAssertEqual(await sendTask.value, .failed(.clientNotFound(clientId)))
        XCTAssertNil(await server.clientPhaseForTesting(clientId))
    }

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: .tcp
        )
    }
}

/// `@unchecked Sendable` justification: send completions and test assertions
/// can arrive from different tasks, and all mutable state is protected by `lock`.
private final class SendCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (NWError?) -> Void)?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func capture(_ handler: @escaping @Sendable (NWError?) -> Void) {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            self.handler = handler
            let waiters = self.waiters
            self.waiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    func waitUntilCaptured() async {
        let isCaptured = lock.withLock { handler != nil }
        guard !isCaptured else { return }
        await withCheckedContinuation { continuation in
            lock.withLock {
                if handler != nil {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }

    func complete(_ error: NWError?) {
        let handler = lock.withLock { self.handler }
        handler?(error)
    }
}
