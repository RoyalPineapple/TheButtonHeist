#if canImport(UIKit)
import XCTest
import UIKit
import TheScore

@testable import TheInsideJob

@MainActor
final class InsideJobRuntimeLifecycleTests: XCTestCase {

    private var originalIdleTimerDisabled = false

    override func setUp() async throws {
        try await super.setUp()
        originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
    }

    override func tearDown() async throws {
        UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
        try await super.tearDown()
    }

    func testStartFromStoppedReachesRunningAndSetsTransport() async throws {
        let harness = makeRuntimeHarness(actualPort: 23456)

        XCTAssertNil(harness.job.transport)
        XCTAssertNil(harness.job.listeningPort)
        try await harness.job.start()

        assertRunning(harness.job, transport: harness.latestTransport(), actualPort: 23456)
        XCTAssertEqual(harness.job.listeningPort, 23456)
        XCTAssertTrue(harness.job.lifecycleObservationIsInstalled)
        XCTAssertEqual(harness.stopCallCount(), 0)

        await harness.job.stop()
        XCTAssertNil(harness.job.listeningPort)
    }

    func testStartWhileRunningDoesNotCreateAnotherRuntime() async throws {
        let harness = makeRuntimeHarness(actualPort: 23456)
        try await harness.job.start()

        guard case .running(let originalResources) = harness.job.serverPhase else {
            return XCTFail("Expected running phase, got \(harness.job.serverPhase)")
        }

        try await harness.job.start()

        guard case .running(let currentResources) = harness.job.serverPhase else {
            return XCTFail("Expected running phase, got \(harness.job.serverPhase)")
        }
        XCTAssertTrue(currentResources.transport === originalResources.transport)
        XCTAssertEqual(currentResources.actualPort, originalResources.actualPort)
        assertRunning(harness.job, transport: harness.latestTransport(), actualPort: 23456)
        XCTAssertEqual(harness.startCallCount(), 1)
        XCTAssertEqual(harness.stopCallCount(), 0)

        await harness.job.stop()
    }

    func testStartWhileStartingDoesNotCreateAnotherRuntime() async throws {
        let startupGate = RuntimeStartGate()
        let harness = makeRuntimeHarness(startOverride: { _, _, _ in
            await startupGate.enterAndWaitForRelease()
            return 23456
        })

        let startTask = Task { @MainActor in
            try await harness.job.start()
        }
        await startupGate.waitUntilEntered()
        guard case .starting = harness.job.serverPhase else {
            return XCTFail("Expected starting phase, got \(harness.job.serverPhase)")
        }

        try await harness.job.start()

        guard case .starting = harness.job.serverPhase else {
            return XCTFail("Expected starting phase, got \(harness.job.serverPhase)")
        }
        XCTAssertEqual(harness.startCallCount(), 1)

        startupGate.release()
        try await startTask.value

        assertRunning(harness.job, transport: harness.latestTransport(), actualPort: 23456)
        XCTAssertEqual(harness.startCallCount(), 1)

        await harness.job.stop()
    }

    func testStopWhileStartingPreventsStaleActivation() async throws {
        let startupGate = RuntimeStartGate()
        let harness = makeRuntimeHarness(startOverride: { _, _, _ in
            await startupGate.enterAndWaitForRelease()
            return 23456
        })

        let startTask = Task { @MainActor in
            try await harness.job.start()
        }
        await startupGate.waitUntilEntered()
        guard case .starting = harness.job.serverPhase else {
            return XCTFail("Expected starting phase, got \(harness.job.serverPhase)")
        }

        await harness.job.stop()
        startupGate.release()

        do {
            try await startTask.value
            XCTFail("Expected stale startup completion to be rejected")
        } catch {}

        assertStoppedClearingLifecycleState(harness.job)
        XCTAssertEqual(harness.startCallCount(), 1)
    }

    func testStartWhileSuspendedDoesNotResumeRuntime() async throws {
        let harness = makeRuntimeHarness(actualPort: 23456)
        try await harness.job.start()

        await harness.job.suspend()
        try await harness.job.start()

        assertSuspendedPreservingLifecycleObservation(harness.job)
        XCTAssertEqual(harness.startCallCount(), 1)
        XCTAssertEqual(harness.stopCallCount(), 1)

        await harness.job.stop()
    }

    func testSuspendFromRunningReachesSuspendedAndPreservesLifecycleObservation() async throws {
        let harness = makeRuntimeHarness()
        try await harness.job.start()

        await harness.job.suspend()

        assertSuspendedPreservingLifecycleObservation(harness.job)
        XCTAssertFalse(harness.job.brains.semanticObservationIsActive)
        XCTAssertFalse(harness.job.brains.stash.semanticObservationStream.isActive)
        XCTAssertFalse(harness.job.tripwire.isPulseRunning)
        XCTAssertEqual(harness.stopCallCount(), 1)

        await harness.job.stop()
    }

    func testDuplicateResumeWhileResumingKeepsSingleAttempt() async throws {
        let resumeStartGate = RuntimeStartGate()
        let harness = makeRuntimeHarness(startOverride: { invocation, _, _ in
            guard invocation > 1 else { return 23456 }
            await resumeStartGate.enterAndWaitForRelease()
            return 23457
        })
        try await harness.job.start()
        await harness.job.suspend()

        await harness.job.resume()
        await resumeStartGate.waitUntilEntered()
        guard case .resuming(let originalAttempt) = harness.job.serverPhase else {
            return XCTFail("Expected resuming phase, got \(harness.job.serverPhase)")
        }

        await harness.job.resume()

        guard case .resuming(let currentAttempt) = harness.job.serverPhase else {
            return XCTFail("Expected resuming phase, got \(harness.job.serverPhase)")
        }
        XCTAssertEqual(currentAttempt.id, originalAttempt.id)
        XCTAssertEqual(harness.startCallCount(), 2)

        resumeStartGate.release()
        await originalAttempt.task.value

        assertRunning(harness.job, transport: harness.latestTransport(), actualPort: 23457)
        XCTAssertEqual(harness.startCallCount(), 2)

        await harness.job.stop()
    }

    func testFailedResumeReturnsToSuspendedAndPreservesLifecycleDiagnostic() async throws {
        let resumeStartGate = RuntimeStartGate()
        let harness = makeRuntimeHarness(startOverride: { invocation, _, _ in
            guard invocation > 1 else { return 23456 }
            await resumeStartGate.enterAndWaitForRelease()
            throw RuntimeStartFailure.resumeFailed
        })
        try await harness.job.start()
        await harness.job.suspend()
        let diagnostic = await recordSettleFailureDiagnostic(on: harness.job)

        await harness.job.resume()
        await resumeStartGate.waitUntilEntered()
        guard case .resuming(let attempt) = harness.job.serverPhase else {
            return XCTFail("Expected resuming phase, got \(harness.job.serverPhase)")
        }

        resumeStartGate.release()
        await attempt.task.value

        assertSuspendedPreservingLifecycleObservation(harness.job)
        XCTAssertEqual(
            harness.job.brains.stash.semanticObservationStream.latestSettleFailureDiagnostic,
            diagnostic
        )
        XCTAssertFalse(harness.job.brains.semanticObservationIsActive)
        XCTAssertFalse(harness.job.brains.stash.semanticObservationStream.isActive)
        XCTAssertFalse(harness.job.tripwire.isPulseRunning)

        await harness.job.stop()
    }

    func testStopFromRunningAndSuspendedReachesStoppedAndClearsLifecycleState() async throws {
        let runningHarness = makeRuntimeHarness()
        try await runningHarness.job.start()

        await runningHarness.job.stop()

        assertStoppedClearingLifecycleState(runningHarness.job)
        XCTAssertEqual(runningHarness.stopCallCount(), 1)

        let suspendedHarness = makeRuntimeHarness()
        try await suspendedHarness.job.start()
        await suspendedHarness.job.suspend()

        await suspendedHarness.job.stop()

        assertStoppedClearingLifecycleState(suspendedHarness.job)
        XCTAssertEqual(suspendedHarness.stopCallCount(), 1)
    }

    private func makeRuntimeHarness(
        actualPort: UInt16 = 34567,
        startOverride: (@MainActor (_ invocation: Int, _ requestedPort: UInt16, _ bindToLoopback: Bool) async throws -> UInt16)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (
        job: TheInsideJob,
        latestTransport: @MainActor () -> ServerTransport,
        startCallCount: @MainActor () -> Int,
        stopCallCount: @MainActor () -> Int
    ) {
        let token = "runtime-lifecycle-test-token"
        let scopes: Set<ConnectionScope> = [.simulator]
        let harnessState = RuntimeHarnessState()

        let job = TheInsideJob(
            token: token,
            allowedScopes: scopes,
            transportFactory: { runtimeToken, runtimeScopes in
                XCTAssertEqual(runtimeToken, token, file: file, line: line)
                XCTAssertEqual(runtimeScopes, scopes, file: file, line: line)
                let transport = ServerTransport(token: token, allowedScopes: scopes)
                transport.startOverride = { requestedPort, bindToLoopback in
                    harnessState.startCount += 1
                    XCTAssertEqual(requestedPort, 0, file: file, line: line)
                    XCTAssertTrue(bindToLoopback, file: file, line: line)
                    if let startOverride {
                        return try await startOverride(harnessState.startCount, requestedPort, bindToLoopback)
                    }
                    return actualPort
                }
                transport.stopOverride = {
                    harnessState.stopCount += 1
                }
                harnessState.transports.append(transport)
                return transport
            }
        )

        return (job, { harnessState.latestTransport }, { harnessState.startCount }, { harnessState.stopCount })
    }

    private func assertRunning(
        _ job: TheInsideJob,
        transport expectedTransport: ServerTransport,
        actualPort: UInt16,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .running(let resources) = job.serverPhase else {
            return XCTFail("Expected running phase, got \(job.serverPhase)", file: file, line: line)
        }
        XCTAssertTrue(resources.transport === expectedTransport, file: file, line: line)
        XCTAssertEqual(resources.actualPort, actualPort, file: file, line: line)
        guard let currentTransport = job.transport else {
            return XCTFail("Expected job transport to be set", file: file, line: line)
        }
        XCTAssertTrue(currentTransport === expectedTransport, file: file, line: line)
        XCTAssertNotNil(job.retainedIdleTimerBaseline, file: file, line: line)
    }

    private func assertSuspendedPreservingLifecycleObservation(
        _ job: TheInsideJob,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .suspended = job.serverPhase else {
            return XCTFail("Expected suspended phase, got \(job.serverPhase)", file: file, line: line)
        }
        XCTAssertNil(job.transport, file: file, line: line)
        XCTAssertTrue(job.lifecycleObservationIsInstalled, file: file, line: line)
        XCTAssertNotNil(job.retainedIdleTimerBaseline, file: file, line: line)
        XCTAssertTrue(job.lifecycleBoundaryTasks.isEmpty, file: file, line: line)
    }

    private func assertStoppedClearingLifecycleState(
        _ job: TheInsideJob,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .stopped = job.serverPhase else {
            return XCTFail("Expected stopped phase, got \(job.serverPhase)", file: file, line: line)
        }
        XCTAssertNil(job.transport, file: file, line: line)
        XCTAssertFalse(job.lifecycleObservationIsInstalled, file: file, line: line)
        XCTAssertTrue(job.lifecycleBoundaryTasks.isEmpty, file: file, line: line)
        XCTAssertFalse(job.brains.semanticObservationIsActive, file: file, line: line)
        XCTAssertFalse(job.brains.stash.semanticObservationStream.isActive, file: file, line: line)
        XCTAssertFalse(job.tripwire.isPulseRunning, file: file, line: line)
        XCTAssertNil(job.retainedIdleTimerBaseline, file: file, line: line)
    }

    private func recordSettleFailureDiagnostic(on job: TheInsideJob) async -> String {
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 17),
            events: [],
            finalScreen: InterfaceObservation.makeForTests(),
            elementsByKey: [:],
            instabilityDescription: "runtime lifecycle diagnostic"
        )
        _ = await job.brains.stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: job.tripwire.tripwireSignal(),
            settleOutcome: outcome
        )
        guard let diagnostic = job.brains.stash.semanticObservationStream.latestSettleFailureDiagnostic else {
            XCTFail("Expected settle failure diagnostic")
            return ""
        }
        XCTAssertTrue(diagnostic.contains("runtime lifecycle diagnostic"))
        return diagnostic
    }

    private enum RuntimeStartFailure: Error {
        case resumeFailed
    }

    private final class RuntimeHarnessState {
        var startCount = 0
        var stopCount = 0
        var transports: [ServerTransport] = []

        var latestTransport: ServerTransport {
            guard let transport = transports.last else {
                fatalError("Expected runtime harness to have created a transport")
            }
            return transport
        }
    }

    @MainActor
    private final class RuntimeStartGate {
        private var entered = false
        private var released = false
        private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

        func enterAndWaitForRelease() async {
            entered = true
            let waiters = enteredWaiters
            enteredWaiters.removeAll()
            waiters.forEach { $0.resume() }

            guard !released else { return }
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }

        func waitUntilEntered() async {
            guard !entered else { return }
            await withCheckedContinuation { continuation in
                enteredWaiters.append(continuation)
            }
        }

        func release() {
            released = true
            let waiters = releaseWaiters
            releaseWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }
}

#endif // canImport(UIKit)
