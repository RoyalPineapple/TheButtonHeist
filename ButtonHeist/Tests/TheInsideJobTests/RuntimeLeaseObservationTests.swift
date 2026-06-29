#if canImport(UIKit)
import XCTest
import UIKit
import ThePlans

@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class RuntimeLeaseObservationTests: XCTestCase {

    private var job: TheInsideJob!
    private var lease: InsideJobRuntimeLease!
    private var originalIdleTimerDisabled = false

    override func setUp() async throws {
        try await super.setUp()
        originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        job = TheInsideJob(token: "runtime-lease-test-token")
        lease = InsideJobRuntimeLease(
            transport: ServerTransport(),
            actualPort: 0,
            bonjourServiceName: nil
        )
    }

    override func tearDown() async throws {
        if let lease, let job {
            await lease.release(from: job, policy: .stop)?.value
        }
        job = nil
        lease = nil
        UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
        try await super.tearDown()
    }

    func testLeaseActivationIsIdempotent() {
        let idleTimerBaseline = UIApplication.shared.isIdleTimerDisabled
        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)
        XCTAssertFalse(job.lifecycleObservationActive)

        lease.activate(on: job)

        XCTAssertTrue(job.brains.semanticObservationIsActive)
        XCTAssertTrue(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertTrue(job.tripwire.isPulseRunning)
        XCTAssertTrue(job.lifecycleObservationActive)
        assertIdleTimerProtection(on: job, engagedWithBaseline: idleTimerBaseline)

        lease.activate(on: job)

        XCTAssertTrue(job.brains.semanticObservationIsActive)
        XCTAssertTrue(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertTrue(job.tripwire.isPulseRunning)
        XCTAssertTrue(job.lifecycleObservationActive)
        assertIdleTimerProtection(on: job, engagedWithBaseline: idleTimerBaseline)
    }

    func testSuspendReleaseStopsRuntimeOwnedObservationButPreservesLifecycleObservation() async {
        let idleTimerBaseline = UIApplication.shared.isIdleTimerDisabled
        lease.activate(on: job)
        XCTAssertTrue(job.brains.semanticObservationIsActive)
        XCTAssertTrue(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertTrue(job.tripwire.isPulseRunning)
        XCTAssertTrue(job.lifecycleObservationActive)

        await lease.release(from: job, policy: .suspend)?.value

        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)
        XCTAssertTrue(job.lifecycleObservationActive)
        assertIdleTimerProtection(on: job, engagedWithBaseline: idleTimerBaseline)
        XCTAssertEqual(UIApplication.shared.isIdleTimerDisabled, idleTimerBaseline)
    }

    func testStopReleaseClearsLifecycleObservationAndIdleTimerBaseline() async {
        let idleTimerBaseline = UIApplication.shared.isIdleTimerDisabled
        lease.activate(on: job)
        XCTAssertTrue(job.lifecycleObservationActive)
        assertIdleTimerProtection(on: job, engagedWithBaseline: idleTimerBaseline)

        await lease.release(from: job, policy: .stop)?.value

        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)
        XCTAssertFalse(job.lifecycleObservationActive)
        assertIdleTimerProtectionIsUnmodified(on: job)
        XCTAssertEqual(UIApplication.shared.isIdleTimerDisabled, idleTimerBaseline)
    }

    func testSuspendReleasePreservesLatestSettleFailureDiagnostic() async {
        lease.activate(on: job)
        let diagnostic = await recordSettleFailureDiagnostic()

        await lease.release(from: job, policy: .suspend)?.value

        XCTAssertEqual(job.brains.stash.semanticObservationStream.latestSettleFailureDiagnostic, diagnostic)
        XCTAssertTrue(job.lifecycleObservationActive)
        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)
    }

    func testStopReleasePreservesLatestSettleFailureDiagnostic() async {
        lease.activate(on: job)
        let diagnostic = await recordSettleFailureDiagnostic()

        await lease.release(from: job, policy: .stop)?.value

        XCTAssertEqual(job.brains.stash.semanticObservationStream.latestSettleFailureDiagnostic, diagnostic)
        XCTAssertFalse(job.lifecycleObservationActive)
        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)
    }

    func testInactiveCommandFailsWithoutStartingObservation() async {
        let result = await job.brains.executeRuntimeAction(.activate(.predicate(ElementPredicate(label: "Save"))))

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .actionFailed)
        XCTAssertEqual(result.message, TheBrains.runtimeInactiveMessage)
        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.brains.stash.semanticObservationStream.isActive)
    }

    private func recordSettleFailureDiagnostic() async -> String {
        let outcome = SettleSession.Outcome(
            outcome: .timedOut(timeMs: 17),
            events: [],
            finalScreen: Screen.makeForTests(),
            elementsByKey: [:],
            instabilityDescription: "runtime lease diagnostic"
        )
        _ = await job.brains.stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: job.tripwire.tripwireSignal(),
            settleOutcome: outcome
        )
        guard let diagnostic = job.brains.stash.semanticObservationStream.latestSettleFailureDiagnostic else {
            XCTFail("Expected settle failure diagnostic")
            return ""
        }
        XCTAssertTrue(diagnostic.contains("runtime lease diagnostic"))
        return diagnostic
    }
}

@MainActor
private func assertIdleTimerProtection(
    on job: TheInsideJob,
    engagedWithBaseline expectedBaseline: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch job.idleTimerProtection {
    case .engaged(let baseline):
        XCTAssertEqual(baseline, expectedBaseline, file: file, line: line)
    case .unmodified:
        XCTFail("Expected idle timer protection to preserve baseline", file: file, line: line)
    }
}

@MainActor
private func assertIdleTimerProtectionIsUnmodified(
    on job: TheInsideJob,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch job.idleTimerProtection {
    case .unmodified:
        break
    case .engaged:
        XCTFail("Expected idle timer protection baseline to be cleared", file: file, line: line)
    }
}

#endif // canImport(UIKit)
