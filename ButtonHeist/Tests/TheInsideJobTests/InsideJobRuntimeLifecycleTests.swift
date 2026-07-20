#if canImport(UIKit)
import XCTest
import UIKit
import ButtonHeistSupport
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
        let harness = try makeRuntimeHarness(actualPort: 23456)

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
        let harness = try makeRuntimeHarness(actualPort: 23456)
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
        let harness = try makeRuntimeHarness(listenerPort: { _ in
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
        let harness = try makeRuntimeHarness(listenerPort: { _ in
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

        let stopTask = Task { @MainActor in
            await harness.job.stop()
        }
        await harness.waitForStopCall()
        startupGate.release()

        let stopOutcome = await stopTask.value
        XCTAssertEqual(stopOutcome, .stopped)

        do {
            try await startTask.value
            XCTFail("Expected stale startup completion to be rejected")
        } catch {}

        assertStoppedClearingLifecycleState(harness.job)
        XCTAssertEqual(harness.startCallCount(), 1)
    }

    func testStartWhileSuspendedDoesNotResumeRuntime() async throws {
        let harness = try makeRuntimeHarness(actualPort: 23456)
        try await harness.job.start()

        await harness.job.suspend()
        try await harness.job.start()

        assertSuspendedPreservingLifecycleObservation(harness.job)
        XCTAssertEqual(harness.startCallCount(), 1)
        XCTAssertEqual(harness.stopCallCount(), 1)

        await harness.job.stop()
    }

    func testSuspendFromRunningReachesSuspendedAndPreservesLifecycleObservation() async throws {
        let harness = try makeRuntimeHarness()
        try await harness.job.start()

        await harness.job.suspend()

        assertSuspendedPreservingLifecycleObservation(harness.job)
        XCTAssertFalse(harness.job.brains.semanticObservationIsActive)
        XCTAssertFalse(harness.job.brains.vault.semanticObservationStream.isActive)
        XCTAssertFalse(harness.job.tripwire.isPulseRunning)
        XCTAssertEqual(harness.stopCallCount(), 1)

        await harness.job.stop()
    }

    func testDuplicateResumeWhileResumingKeepsSingleAttempt() async throws {
        let resumeStartGate = RuntimeStartGate()
        let harness = try makeRuntimeHarness(listenerPort: { invocation in
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
        let harness = try makeRuntimeHarness(listenerPort: { invocation in
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
            harness.job.brains.vault.semanticObservationStream.latestSettleFailureDiagnostic,
            diagnostic
        )
        XCTAssertFalse(harness.job.brains.semanticObservationIsActive)
        XCTAssertFalse(harness.job.brains.vault.semanticObservationStream.isActive)
        XCTAssertFalse(harness.job.tripwire.isPulseRunning)

        await harness.job.stop()
    }

    func testStopFromRunningAndSuspendedReachesStoppedAndClearsLifecycleState() async throws {
        let runningHarness = try makeRuntimeHarness()
        try await runningHarness.job.start()

        await runningHarness.job.stop()

        assertStoppedClearingLifecycleState(runningHarness.job)
        XCTAssertEqual(runningHarness.stopCallCount(), 1)

        let suspendedHarness = try makeRuntimeHarness()
        try await suspendedHarness.job.start()
        await suspendedHarness.job.suspend()

        await suspendedHarness.job.stop()

        assertStoppedClearingLifecycleState(suspendedHarness.job)
        XCTAssertEqual(suspendedHarness.stopCallCount(), 1)
    }

    private func makeRuntimeHarness(
        actualPort: UInt16 = 34567,
        listenerPort: (@MainActor (_ invocation: Int) async throws -> UInt16)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws(InsideJobConfigurationError) -> (
        job: TheInsideJob,
        latestTransport: @MainActor () -> ServerTransport,
        startCallCount: @MainActor () -> Int,
        stopCallCount: @MainActor () -> Int,
        waitForStopCall: @MainActor () async -> Void
    ) {
        let token: SessionAuthToken = "runtime-lifecycle-test-token"
        let scopes: Set<ConnectionScope> = [.simulator]
        let harnessState = RuntimeHarnessState()

        let job = try TheInsideJob(
            token: token.description,
            allowedScopes: scopes,
            addressFamily: .ipv4,
            transportFactory: { runtimeToken, runtimeScopes in
                XCTAssertEqual(runtimeToken, token, file: file, line: line)
                XCTAssertEqual(runtimeScopes, scopes, file: file, line: line)
                let listeners = TestSocketListenerFactory(
                    start: { _ in
                        harnessState.startCount += 1
                        if let listenerPort {
                            do {
                                return .ready(try await listenerPort(harnessState.startCount))
                            } catch {
                                return .failed(.posix(.ECONNABORTED))
                            }
                        }
                        return .ready(actualPort)
                    },
                    onCancel: { harnessState.recordStop() }
                )
                let transport = ServerTransport(
                    token: token,
                    allowedScopes: scopes,
                    serverDependencies: .init(
                        listenerFactory: listeners.listenerFactory
                    )
                )
                harnessState.transports.append(transport)
                return transport
            }
        )

        return (
            job,
            { harnessState.latestTransport },
            { harnessState.startCount },
            { harnessState.stopCount },
            { await harnessState.waitForStopCall() }
        )
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
        XCTAssertFalse(job.brains.semanticObservationIsActive, file: file, line: line)
        XCTAssertFalse(job.brains.vault.semanticObservationStream.isActive, file: file, line: line)
        XCTAssertFalse(job.tripwire.isPulseRunning, file: file, line: line)
        XCTAssertNil(job.retainedIdleTimerBaseline, file: file, line: line)
    }

    private func recordSettleFailureDiagnostic(on job: TheInsideJob) async -> String {
        let settleResult = SettleSession.Result(
            outcome: .timedOut(timeMs: 17),
            events: [],
            finalObservation: SettleSessionFinalObservation(
                observation: InterfaceObservation.makeForTests()
            ),
            elementsByKey: [:],
            tripwireSignal: job.brains.vault.semanticObservationStream.currentTripwireSignal(),
            instabilityDescription: "runtime lifecycle diagnostic"
        )
        _ = await job.brains.vault.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: job.tripwire.tripwireSignal(),
            settleResult: settleResult
        )
        guard let diagnostic = job.brains.vault.semanticObservationStream.latestSettleFailureDiagnostic else {
            XCTFail("Expected settle failure diagnostic")
            return ""
        }
        XCTAssertTrue(diagnostic.contains("runtime lifecycle diagnostic"))
        return diagnostic
    }

    private enum RuntimeStartFailure: Error {
        case resumeFailed
    }

    @MainActor
    private final class RuntimeHarnessState {
        var startCount = 0
        private(set) var stopCount = 0
        var transports: [ServerTransport] = []
        private let stopCalled = CompletionSignal()

        var latestTransport: ServerTransport {
            guard let transport = transports.last else {
                fatalError("Expected runtime harness to have created a transport")
            }
            return transport
        }

        func recordStop() {
            stopCount += 1
            stopCalled.finish()
        }

        func waitForStopCall() async {
            await stopCalled.wait()
        }
    }

    @MainActor
    private final class RuntimeStartGate {
        private let entered = CompletionSignal()
        private let released = CompletionSignal()

        func enterAndWaitForRelease() async {
            entered.finish()
            await released.wait()
        }

        func waitUntilEntered() async {
            await entered.wait()
        }

        func release() {
            released.finish()
        }
    }
}

#endif // canImport(UIKit)
