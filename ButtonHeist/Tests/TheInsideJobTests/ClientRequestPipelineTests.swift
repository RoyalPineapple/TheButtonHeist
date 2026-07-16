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

    var hasSignalled: Bool { isSignalled }
}

final class TheBrainsInteractionRequestTests: XCTestCase {
    @MainActor
    func testAdmissionStopsAtPendingCapacity() async {
        let brains = TheBrains(tripwire: TheTripwire())
        let activeGate = PipelineTestGate()

        XCTAssertEqual(brains.submitTransportRequest(clientId: 0) {
            await activeGate.suspend()
        }, .accepted)
        await activeGate.entered.wait()

        for clientId in 1...64 {
            XCTAssertEqual(brains.submitTransportRequest(clientId: clientId) {}, .accepted)
        }
        XCTAssertEqual(
            brains.interactionRequestSnapshot,
            .init(phase: .running, pendingDepth: 64, capacity: 64)
        )
        XCTAssertEqual(
            brains.submitTransportRequest(clientId: 65) {},
            .rejected(.busy(capacity: 64))
        )
        XCTAssertEqual(brains.interactionRequestSnapshot.pendingDepth, 64)

        activeGate.release()
        await brains.stopInteractionRequests()
    }

    @MainActor
    func testOwnerCancellationRetainsOtherQueuedRequestsInFIFOOrder() async {
        let brains = TheBrains(tripwire: TheTripwire())
        let activeGate = PipelineTestGate()
        let retainedCompleted = PipelineTestSignal()
        var trace: [String] = []

        brains.submitTransportRequest(clientId: 1) {
            trace.append("active")
            await activeGate.suspend()
        }
        await activeGate.entered.wait()
        brains.submitTransportRequest(clientId: 2) {
            trace.append("cancelled")
        }
        brains.submitTransportRequest(clientId: 3) {
            trace.append("retained")
            retainedCompleted.signal()
        }

        brains.cancelTransportRequests(clientId: 2)
        activeGate.release()
        await retainedCompleted.wait()
        XCTAssertEqual(trace, ["active", "retained"])
        await brains.stopInteractionRequests()
    }

    @MainActor
    func testCancelledActiveRequestFinishesCleanupBeforeQueueAdvances() async {
        let brains = TheBrains(tripwire: TheTripwire())
        let activeGate = PipelineTestGate()
        let nextGate = PipelineTestGate()
        let lastCompleted = PipelineTestSignal()
        var trace: [String] = []

        brains.submitTransportRequest(clientId: 1) {
            trace.append("active-start")
            await activeGate.suspend()
            trace.append("active-cleanup")
        }
        await activeGate.entered.wait()
        brains.submitTransportRequest(clientId: 2) {
            trace.append("next-start")
            await nextGate.suspend()
            trace.append("next-finish")
        }
        brains.submitTransportRequest(clientId: 3) {
            trace.append("last")
            lastCompleted.signal()
        }

        brains.cancelTransportRequests(clientId: 1)
        XCTAssertEqual(trace, ["active-start"])

        activeGate.release()
        await nextGate.entered.wait()
        XCTAssertEqual(trace, ["active-start", "active-cleanup", "next-start"])
        XCTAssertFalse(lastCompleted.hasSignalled)

        brains.cancelTransportRequests(clientId: 1)
        nextGate.release()
        await lastCompleted.wait()
        XCTAssertEqual(
            trace,
            ["active-start", "active-cleanup", "next-start", "next-finish", "last"]
        )
        await brains.stopInteractionRequests()
    }

    @MainActor
    func testDrainWaitsForCancellationInsensitiveCleanup() async {
        let brains = TheBrains(tripwire: TheTripwire())
        let activeGate = PipelineTestGate()
        let drainCompleted = PipelineTestSignal()
        let joinedDrainCompleted = PipelineTestSignal()

        let active = Task { @MainActor in
            await brains.executeInAppRequest {
                await activeGate.suspend()
            }
        }
        await activeGate.entered.wait()

        let drain = Task { @MainActor in
            await brains.stopInteractionRequests()
            drainCompleted.signal()
        }
        guard case .cancelled = await active.value else {
            activeGate.release()
            await drain.value
            return XCTFail("Expected drain to cancel the active request outcome")
        }
        XCTAssertFalse(drainCompleted.hasSignalled)
        guard case .rejected(.stopping) = await brains.executeInAppRequest({}) else {
            activeGate.release()
            await drain.value
            return XCTFail("Expected stopping rejection to resolve its completion")
        }
        let joinedDrain = Task { @MainActor in
            await brains.stopInteractionRequests()
            joinedDrainCompleted.signal()
        }

        activeGate.release()
        await drain.value
        await joinedDrain.value
        XCTAssertTrue(drainCompleted.hasSignalled)
        XCTAssertTrue(joinedDrainCompleted.hasSignalled)
        guard case .completed(let value) = await brains.executeInAppRequest({ "ready" }) else {
            return XCTFail("Expected requests to resume after drain")
        }
        XCTAssertEqual(value, "ready")
    }

    @MainActor
    func testCancellationDeadlinePoisonsAdmissionUntilCleanupFinishes() async {
        let deadline = ManualInteractionCleanupDeadline()
        let executor = InteractionRequestExecutor(
            cleanupDeadlineScheduler: deadline.schedule
        )
        let activeGate = PipelineTestGate()
        var activeCancellationCount = 0
        var queuedCancellationCount = 0

        XCTAssertEqual(executor.submit(owner: .transportClient(1), operation: {
            await activeGate.suspend()
        }, completion: { outcome in
            if case .cancelled = outcome {
                activeCancellationCount += 1
            }
        }), .accepted)
        await activeGate.entered.wait()
        XCTAssertEqual(executor.submit(owner: .transportClient(2), operation: {}, completion: { outcome in
            if case .cancelled = outcome {
                queuedCancellationCount += 1
            }
        }), .accepted)

        executor.cancel(owner: .transportClient(1))
        XCTAssertEqual(activeCancellationCount, 1)
        XCTAssertEqual(
            executor.snapshot,
            .init(phase: .cancelling, pendingDepth: 1, capacity: 64)
        )

        deadline.fire()
        XCTAssertEqual(queuedCancellationCount, 1)
        XCTAssertEqual(
            executor.snapshot,
            .init(phase: .cleanupTimedOut, pendingDepth: 0, capacity: 64)
        )
        XCTAssertEqual(
            executor.submit(owner: .transportClient(3), operation: {}, completion: { _ in }),
            .rejected(.cleanupTimedOut)
        )

        let drainStarted = PipelineTestSignal()
        let drain = Task { @MainActor in
            drainStarted.signal()
            await executor.drain()
        }
        await drainStarted.wait()
        XCTAssertEqual(executor.snapshot.phase, .stopping)
        activeGate.release()
        await drain.value
        XCTAssertEqual(executor.snapshot, .init(phase: .idle, pendingDepth: 0, capacity: 64))
        XCTAssertEqual(activeCancellationCount, 1)
    }
}

@MainActor
private final class ManualInteractionCleanupDeadline {
    private var deadlineReached: (@MainActor @Sendable () -> Void)?

    func schedule(
        _ deadlineReached: @escaping @MainActor @Sendable () -> Void
    ) -> Task<Void, Never> {
        self.deadlineReached = deadlineReached
        return Task {}
    }

    func fire() {
        let operation = deadlineReached
        deadlineReached = nil
        operation?()
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
    func testSameClientControlProgressesAndDisconnectCancelsLaterUIWork() async {
        let brains = TheBrains(tripwire: TheTripwire())
        let uiGate = PipelineTestGate()
        let controlCompleted = PipelineTestSignal()
        var controlTrace: [String] = []
        var secondUIExecuted = false
        let pipeline = ClientRequestPipeline { request in
            switch request.text {
            case "first-ui":
                brains.submitTransportRequest(clientId: request.clientId) {
                    await uiGate.suspend()
                }
            case "ping":
                controlTrace.append("ping")
            case "status":
                controlTrace.append("status")
                controlCompleted.signal()
            case "second-ui":
                brains.submitTransportRequest(clientId: request.clientId) {
                    secondUIExecuted = true
                }
            default:
                XCTFail("Unexpected request")
            }
        }

        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "first-ui")), .enqueued)
        await uiGate.entered.wait()
        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "ping")), .enqueued)
        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "status")), .enqueued)
        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "second-ui")), .enqueued)
        await controlCompleted.wait()
        XCTAssertEqual(controlTrace, ["ping", "status"])
        XCTAssertFalse(secondUIExecuted)

        let consumer = pipeline.stop()
        brains.cancelTransportRequests(clientId: 1)
        XCTAssertEqual(brains.interactionRequestSnapshot.phase, .cancelling)
        uiGate.release()
        await brains.stopInteractionRequests()
        await consumer?.value
        XCTAssertFalse(secondUIExecuted)
    }

    @MainActor
    func testAdmissionOverflowStopsAtItsNamedCapacity() async throws {
        let activeGate = PipelineTestGate()
        var executedRequestIds: [String] = []
        let pipeline = ClientRequestPipeline { request in
            executedRequestIds.append(request.text)
            await activeGate.suspend()
        }

        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "active")), .enqueued)
        await activeGate.entered.wait()
        for requestIndex in 0..<ClientRequestPipeline.maximumQueuedRequests {
            let requestID = try RequestID(validating: "queued-\(requestIndex)")
            XCTAssertEqual(
                pipeline.enqueue(request(clientId: 1, requestId: requestID)),
                .enqueued
            )
        }

        XCTAssertEqual(
            pipeline.enqueue(request(clientId: 1, requestId: "overflow")),
            .overflowed
        )
        XCTAssertEqual(pipeline.enqueue(request(clientId: 1, requestId: "late")), .stopped)

        let consumer = pipeline.stop()
        activeGate.release()
        await consumer?.value
        XCTAssertEqual(executedRequestIds, ["active"])
    }

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
