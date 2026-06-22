#if canImport(UIKit)
import XCTest
import ThePlans

@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class RuntimeLeaseObservationTests: XCTestCase {

    private var job: TheInsideJob!
    private var lease: InsideJobRuntimeLease!

    override func setUp() async throws {
        try await super.setUp()
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
        try await super.tearDown()
    }

    func testLeaseActivationStartsSemanticObservationOnce() {
        XCTAssertFalse(job.brains.semanticObservationIsActive)
        XCTAssertFalse(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertFalse(job.tripwire.isPulseRunning)

        lease.activate(on: job)

        XCTAssertTrue(job.brains.semanticObservationIsActive)
        XCTAssertTrue(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertTrue(job.tripwire.isPulseRunning)

        lease.activate(on: job)

        XCTAssertTrue(job.brains.semanticObservationIsActive)
        XCTAssertTrue(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertTrue(job.tripwire.isPulseRunning)
    }

    func testLeaseReleaseStopsRuntimeOwnedObservation() async {
        lease.activate(on: job)
        XCTAssertTrue(job.brains.semanticObservationIsActive)
        XCTAssertTrue(job.brains.stash.semanticObservationStream.isActive)
        XCTAssertTrue(job.tripwire.isPulseRunning)

        await lease.release(from: job, policy: .stop)?.value

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
}

#endif // canImport(UIKit)
