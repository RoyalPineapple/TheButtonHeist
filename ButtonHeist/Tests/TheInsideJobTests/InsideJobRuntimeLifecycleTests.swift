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
        try await harness.job.start()

        assertRunning(harness.job, transport: harness.transport, actualPort: 23456)
        XCTAssertTrue(harness.job.lifecycleObservationActive)
        XCTAssertEqual(harness.stopCallCount(), 0)

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
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (
        job: TheInsideJob,
        transport: ServerTransport,
        stopCallCount: @MainActor () -> Int
    ) {
        let token = "runtime-lifecycle-test-token"
        let scopes: Set<ConnectionScope> = [.simulator]
        let transport = ServerTransport(token: token, allowedScopes: scopes)
        let stopCounter = StopCounter()

        transport.startOverride = { requestedPort, bindToLoopback in
            XCTAssertEqual(requestedPort, 0, file: file, line: line)
            XCTAssertTrue(bindToLoopback, file: file, line: line)
            return actualPort
        }
        transport.stopOverride = {
            stopCounter.value += 1
            return Task {}
        }

        let job = TheInsideJob(
            token: token,
            allowedScopes: scopes,
            transportFactory: { runtimeToken, runtimeScopes in
                XCTAssertEqual(runtimeToken, token, file: file, line: line)
                XCTAssertEqual(runtimeScopes, scopes, file: file, line: line)
                return transport
            }
        )

        return (job, transport, { stopCounter.value })
    }

    private func assertRunning(
        _ job: TheInsideJob,
        transport expectedTransport: ServerTransport,
        actualPort: UInt16,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .running(let lease) = job.serverPhase else {
            return XCTFail("Expected running phase, got \(job.serverPhase)", file: file, line: line)
        }
        XCTAssertTrue(lease.transport === expectedTransport, file: file, line: line)
        XCTAssertEqual(lease.actualPort, actualPort, file: file, line: line)
        guard let currentTransport = job.transport else {
            return XCTFail("Expected job transport to be set", file: file, line: line)
        }
        XCTAssertTrue(currentTransport === expectedTransport, file: file, line: line)
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
        XCTAssertTrue(job.lifecycleObservationActive, file: file, line: line)
        XCTAssertNil(job.pendingForegroundResumeTask, file: file, line: line)
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
        XCTAssertFalse(job.lifecycleObservationActive, file: file, line: line)
        XCTAssertNil(job.pendingForegroundResumeTask, file: file, line: line)
        XCTAssertTrue(job.lifecycleBoundaryTasks.isEmpty, file: file, line: line)
        XCTAssertFalse(job.brains.semanticObservationIsActive, file: file, line: line)
        XCTAssertFalse(job.brains.stash.semanticObservationStream.isActive, file: file, line: line)
        XCTAssertFalse(job.tripwire.isPulseRunning, file: file, line: line)

        switch job.idleTimerProtection {
        case .unmodified:
            break
        case .engaged:
            XCTFail("Expected idle timer baseline to be cleared", file: file, line: line)
        }
    }

    private final class StopCounter {
        var value = 0
    }
}

#endif // canImport(UIKit)
