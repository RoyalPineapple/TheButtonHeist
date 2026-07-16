import XCTest

@testable import TheInsideJob
import TheScore

@MainActor
private final class PipelineTestSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !isSignalled else { return }
        isSignalled = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

final class InteractionRequestExecutorTests: XCTestCase {
    @MainActor
    func testTransportAndInAppRequestsShareOneFIFO() async {
        let brains = TheBrains(tripwire: TheTripwire())
        let firstBlocked = PipelineTestGate()
        let secondSubmitted = PipelineTestSignal()
        var trace: [String] = []

        let first = Task { @MainActor in
            await brains.submitTransportRequest(clientId: 1) {
                trace.append("first-start")
                await firstBlocked.suspend()
                trace.append("first-finish")
            }
        }
        await firstBlocked.entered.wait()

        let second = Task { @MainActor in
            secondSubmitted.signal()
            await brains.executeInAppRequest {
                trace.append("second")
            }
        }
        await secondSubmitted.wait()

        XCTAssertEqual(trace, ["first-start"])
        firstBlocked.release()
        await first.value
        await second.value
        XCTAssertEqual(trace, ["first-start", "first-finish", "second"])
    }

    @MainActor
    func testDisconnectCancelsQueuedClientUIWork() async {
        let brains = TheBrains(tripwire: TheTripwire())
        let activeBlocked = PipelineTestGate()
        let queuedSubmitted = PipelineTestSignal()
        var trace: [String] = []

        let active = Task { @MainActor in
            await brains.submitTransportRequest(clientId: 1) {
                trace.append("active")
                await activeBlocked.suspend()
            }
        }
        await activeBlocked.entered.wait()

        let queued = Task { @MainActor in
            queuedSubmitted.signal()
            await brains.submitTransportRequest(clientId: 2) {
                trace.append("cancelled")
            }
        }
        await queuedSubmitted.wait()

        brains.cancelTransportRequests(clientId: 2)
        activeBlocked.release()
        await active.value
        await queued.value

        XCTAssertEqual(trace, ["active"])
    }
}

@MainActor
private final class PipelineTestGate {
    let entered = PipelineTestSignal()
    private let released = PipelineTestSignal()

    func suspend() async {
        entered.signal()
        await released.wait()
    }

    func release() {
        released.signal()
    }
}

final class ClientRequestPipelineTests: XCTestCase {
    @MainActor
    func testBlockedClientDoesNotDelayAnotherClient() async {
        let blocked = PipelineTestGate()
        let otherClientCompleted = PipelineTestSignal()
        let first = ClientRequestPipeline { request in
            if request.text == "blocked" {
                await blocked.suspend()
            }
        }
        let second = ClientRequestPipeline { request in
            if request.text == "ping" {
                otherClientCompleted.signal()
            }
        }

        XCTAssertEqual(first.enqueue(request(clientId: 1, requestId: "blocked")), .enqueued)
        await blocked.entered.wait()
        XCTAssertEqual(second.enqueue(request(clientId: 2, requestId: "ping")), .enqueued)

        await otherClientCompleted.wait()

        blocked.release()
        let firstConsumer = first.stop()
        let secondConsumer = second.stop()
        await firstConsumer?.value
        await secondConsumer?.value
    }

    @MainActor
    func testRequestsFromOneClientExecuteInExactOrder() async {
        let blocked = PipelineTestGate()
        let secondCompleted = PipelineTestSignal()
        var trace: [String] = []
        let pipeline = ClientRequestPipeline { request in
            let requestId = request.text
            trace.append("start-\(requestId)")
            if requestId == "first" {
                await blocked.suspend()
            }
            trace.append("finish-\(requestId)")
            if requestId == "second" {
                secondCompleted.signal()
            }
        }

        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "first")), .enqueued)
        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "second")), .enqueued)
        await blocked.entered.wait()
        XCTAssertEqual(trace, ["start-first"])

        blocked.release()
        await secondCompleted.wait()

        XCTAssertEqual(trace, ["start-first", "finish-first", "start-second", "finish-second"])
        let consumer = pipeline.stop()
        await consumer?.value
    }

    @MainActor
    func testStopCancelsQueuedClientWork() async {
        let blocked = PipelineTestGate()
        var executedRequestIds: [String] = []
        let pipeline = ClientRequestPipeline { request in
            let requestId = request.text
            executedRequestIds.append(requestId)
            if requestId == "active" {
                await blocked.suspend()
            }
        }

        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "active")), .enqueued)
        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "queued")), .enqueued)
        await blocked.entered.wait()

        let consumer = pipeline.stop()
        blocked.release()
        await consumer?.value

        XCTAssertEqual(executedRequestIds, ["active"])
        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "late")), .stopped)
    }

    @MainActor
    private func request(clientId: Int, requestId: RequestID) -> ClientTransportRequest {
        ClientTransportRequest(
            clientId: clientId,
            data: Data(requestId.description.utf8),
            respond: { _ in .delivered }
        )
    }
}

private extension ClientTransportRequest {
    var text: String {
        String(bytes: data, encoding: .utf8) ?? ""
    }
}
