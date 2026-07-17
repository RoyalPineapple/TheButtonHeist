#if canImport(UIKit)
#if DEBUG
import XCTest

@testable import TheInsideJob

@MainActor
final class PredicateWaitLifecycleTests: XCTestCase {
    func testLifecycleMachineCarriesEvidenceThroughDeadlineSequence() {
        let machine = PredicateWaitLifecycleMachine<String>(continuesAfterInitialMiss: true)
        var state = PredicateWaitLifecycleState<String>.initialVisible("initial")
        let steps: [(
            event: PredicateWaitLifecycleEvent<String>,
            transition: PredicateWaitLifecycleTransition<String>
        )] = [
            (
                .evaluated(.init(evidence: "visible", matched: false)),
                .advanced(.initialDiscovery("visible"), effect: .discover(.overall))
            ),
            (
                .evaluated(.init(evidence: "discovery", matched: false)),
                .advanced(.awaitingObservation("discovery"), effect: .awaitObservation)
            ),
            (
                .deadlineReached,
                .advanced(.terminalVisible("discovery"), effect: .settleVisible(.viewportTransition))
            ),
            (
                .evaluated(.init(evidence: "terminal visible", matched: false)),
                .advanced(.terminalDiscovery("terminal visible"), effect: .discover(.unbounded))
            ),
            (
                .evaluated(.init(evidence: "terminal discovery", matched: false)),
                .advanced(.finished(.timedOut, "terminal discovery"), effect: .finish(.timedOut))
            ),
        ]

        for step in steps {
            let transition = machine.advance(state, with: step.event)
            XCTAssertEqual(transition, step.transition)
            state = transition.state
        }

        XCTAssertEqual(state.phase, .finished(.timedOut))
        XCTAssertEqual(state.evidence, "terminal discovery")
    }

    func testImmediateCaseSelectionMissFinishesInLifecycleMachine() {
        let machine = PredicateWaitLifecycleMachine<String>(continuesAfterInitialMiss: false)

        let transition = machine.advance(
            .initialVisible("unevaluated"),
            with: .evaluated(.init(evidence: "evaluated", matched: false))
        )

        XCTAssertEqual(
            transition,
            .advanced(.finished(.timedOut, "evaluated"), effect: .finish(.timedOut))
        )
    }

    func testIllegalEventsRemainTypedRejections() {
        let machine = PredicateWaitLifecycleMachine<String>(continuesAfterInitialMiss: true)
        let cases: [(
            state: PredicateWaitLifecycleState<String>,
            event: PredicateWaitLifecycleEvent<String>,
            rejection: PredicateWaitLifecycleRejection
        )] = [
            (.initialVisible("initial"), .deadlineReached, .unexpectedEvent),
            (.finished(.matched, "matched"), .deadlineReached, .alreadyFinished),
        ]

        for testCase in cases {
            XCTAssertEqual(
                machine.advance(testCase.state, with: testCase.event),
                .rejected(testCase.rejection, state: testCase.state)
            )
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
