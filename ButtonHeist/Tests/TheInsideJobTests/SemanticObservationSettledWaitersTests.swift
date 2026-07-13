#if canImport(UIKit)
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class SemanticObservationSettledWaitersTests: XCTestCase {
    private var stash: TheStash!

    override func setUp() async throws {
        stash = TheStash(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        stash.stopPassiveSemanticObservation()
        stash = nil
    }

    func testCancelAllCannotDeliverObservation() async {
        let waiters = SemanticObservationSettledWaiters()
        let waiter = waitingTask(in: waiters, scope: .visible)
        await waitForRegistration(in: waiters)

        waiters.cancelAll()

        let result = await waiter.value
        XCTAssertNil(result)
        XCTAssertEqual(waiters.count, 0)
    }

    func testPublicationRejectsEventWhoseScopeDoesNotMatchDictionaryKey() async {
        let visibleEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Visible", heistId: "visible")
        )
        let waiters = SemanticObservationSettledWaiters()
        let waiter = waitingTask(in: waiters, scope: .discovery)
        await waitForRegistration(in: waiters)

        waiters.completeWaiters(with: [.discovery: visibleEvent])

        XCTAssertEqual(waiters.count, 1)
        waiters.cancelAll()
        let result = await waiter.value
        XCTAssertNil(result)
    }

    private func waitingTask(
        in waiters: SemanticObservationSettledWaiters,
        scope: SemanticObservationScope
    ) -> Task<SettledSemanticObservationEvent?, Never> {
        Task { @MainActor in
            await waiters.wait(
                scope: scope,
                afterSequence: nil,
                timeout: nil,
                currentEvent: { nil }
            )
        }
    }

    private func waitForRegistration(in waiters: SemanticObservationSettledWaiters) async {
        for _ in 0..<20 where waiters.count == 0 {
            await Task.yield()
        }
        XCTAssertEqual(waiters.count, 1)
    }

    private func observation(label: String, heistId: HeistId) -> InterfaceObservation {
        .makeForTests(elements: [
            (AccessibilityElement.make(label: label, traits: .header), heistId),
        ])
    }
}

#endif
