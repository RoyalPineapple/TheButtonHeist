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
        let registered = expectation(description: "Waiter registered")
        let waiter = waitingTask(in: waiters, scope: .visible, registered: registered)
        await fulfillment(of: [registered], timeout: 1.0)

        waiters.cancelAll()

        let result = await waiter.value
        XCTAssertNil(result)
        XCTAssertEqual(waiters.count, 0)
    }

    func testPublicationCompletesOnlyWaitersForEventScope() async {
        let visibleEvent = stash.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: "Visible", heistId: "visible")
        )
        let waiters = SemanticObservationSettledWaiters()
        let visibleRegistered = expectation(description: "Visible waiter registered")
        let discoveryRegistered = expectation(description: "Discovery waiter registered")
        let visibleWaiter = waitingTask(in: waiters, scope: .visible, registered: visibleRegistered)
        let discoveryWaiter = waitingTask(in: waiters, scope: .discovery, registered: discoveryRegistered)
        await fulfillment(of: [visibleRegistered, discoveryRegistered], timeout: 1.0)

        waiters.completeWaiters(with: [visibleEvent])

        let visibleResult = await visibleWaiter.value
        XCTAssertEqual(visibleResult?.scope, .visible)
        XCTAssertEqual(waiters.count, 1)
        waiters.cancelAll()
        let discoveryResult = await discoveryWaiter.value
        XCTAssertNil(discoveryResult)
    }

    private func waitingTask(
        in waiters: SemanticObservationSettledWaiters,
        scope: SemanticObservationScope,
        registered: XCTestExpectation
    ) -> Task<SettledSemanticObservationEvent?, Never> {
        Task { @MainActor in
            await waiters.wait(
                scope: scope,
                afterSequence: nil,
                timeout: nil,
                onRegistered: {
                    registered.fulfill()
                },
                currentEvent: { nil }
            )
        }
    }

    private func observation(label: String, heistId: HeistId) -> InterfaceObservation {
        .makeForTests(elements: [
            (AccessibilityElement.make(label: label, traits: .header), heistId),
        ])
    }
}

#endif
