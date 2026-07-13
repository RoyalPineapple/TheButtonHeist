#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

final class PredicatePollingReducerTests: XCTestCase {
    func testStartTransitionsFromIdleOrExplicitlySkips() {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let idleState = PredicatePollingState(
            observedSequence: 4,
            initialVisibleFingerprint: .unknown,
            scope: .visible,
            needsInitialProbe: false
        )
        let started = reducer.start(scope: .visible, initialObservedSequence: 4)

        XCTAssertNotEqual(started.state, idleState)
        XCTAssertEqual(started.effect, .observe(.visibleImmediate(after: 4)))

        let skippedReducer = PredicatePollingReducer(timeout: 0, pollWhenTimeoutZero: false)
        let skippedIdleState = PredicatePollingState(
            observedSequence: nil,
            initialVisibleFingerprint: .unknown,
            scope: .discovery,
            needsInitialProbe: true
        )
        let skipped = skippedReducer.start(scope: .discovery, initialObservedSequence: nil)

        XCTAssertNotEqual(skipped.state, skippedIdleState)
        XCTAssertEqual(skipped.state.nextProbe, .discovery)
        XCTAssertEqual(skipped.effect, .finish(.notPolled))
    }

    func testVisibleObservedTransitionsImmediateAndSettledPhases() {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let immediate = reducer.start(scope: .visible, initialObservedSequence: nil)
        let settled = reducer.reduce(
            immediate.state,
            event: .visibleObserved(
                PredicatePollingVisibleObservation(
                    sequence: 1,
                    fingerprint: .known("visible-a"),
                    matched: false
                ),
                timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0.01)
            )
        )

        XCTAssertNotEqual(settled.state, immediate.state)
        XCTAssertEqual(
            settled.effect,
            .observe(.visibleSettled(after: 1, timeout: SemanticObservationTiming.visibleTickIntervalSeconds))
        )

        let visibleFallback = reducer.reduce(
            settled.state,
            event: .visibleUnavailable(timing: PredicatePollingTickTiming(remaining: 0.8, elapsed: 0))
        )

        XCTAssertNotEqual(visibleFallback.state, settled.state)
        XCTAssertEqual(
            visibleFallback.effect,
            .sleep(PredicatePollingSleep(duration: SemanticObservationTiming.visibleTickIntervalSeconds))
        )

        let matched = reducer.reduce(
            settled.state,
            event: .visibleObserved(
                PredicatePollingVisibleObservation(
                    sequence: 2,
                    fingerprint: .known("visible-b"),
                    matched: true
                ),
                timing: PredicatePollingTickTiming(remaining: 0.8, elapsed: 0.02)
            )
        )
        let expectedFinishedState = PredicatePollingReducer(timeout: 0, pollWhenTimeoutZero: false)
            .start(scope: .visible, initialObservedSequence: 2)
            .state

        XCTAssertEqual(matched.state, expectedFinishedState)
        XCTAssertEqual(matched.effect, .finish(.matched))
    }

    func testVisibleUnavailableTransitionsImmediateAndSettledPhases() {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let immediate = reducer.start(scope: .visible, initialObservedSequence: 3)
        let settled = reducer.reduce(
            immediate.state,
            event: .visibleUnavailable(timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0))
        )

        XCTAssertNotEqual(settled.state, immediate.state)
        XCTAssertEqual(
            settled.effect,
            .observe(.visibleSettled(after: 3, timeout: SemanticObservationTiming.visibleTickIntervalSeconds))
        )

        let sleeping = reducer.reduce(
            settled.state,
            event: .visibleUnavailable(timing: PredicatePollingTickTiming(remaining: 0.8, elapsed: 0))
        )

        XCTAssertNotEqual(sleeping.state, settled.state)
        XCTAssertEqual(
            sleeping.effect,
            .sleep(PredicatePollingSleep(duration: SemanticObservationTiming.visibleTickIntervalSeconds))
        )

        let discovery = awaitingDiscoveryReduction(reducer)

        XCTAssertEqual(discovery.state.nextProbe, .discovery)
        XCTAssertEqual(discovery.effect, .observe(.discovery(after: nil, timeout: 1)))
    }

    func testDiscoveryEventsTransitionToMatchingOrSleeping() {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let discovery = awaitingDiscoveryReduction(reducer)
        let observedNoMatch = reducer.reduce(
            discovery.state,
            event: .discoveryObserved(
                PredicatePollingDiscoveryObservation(sequence: 1, matched: false),
                timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0)
            )
        )

        XCTAssertNotEqual(observedNoMatch.state, discovery.state)
        XCTAssertEqual(observedNoMatch.state.nextProbe, .visible)
        XCTAssertEqual(
            observedNoMatch.effect,
            .sleep(PredicatePollingSleep(duration: SemanticObservationTiming.visibleTickIntervalSeconds))
        )

        let unavailable = reducer.reduce(
            discovery.state,
            event: .discoveryUnavailable(timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0))
        )

        XCTAssertNotEqual(unavailable.state, discovery.state)
        XCTAssertEqual(unavailable.state.nextProbe, .discovery)
        XCTAssertEqual(
            unavailable.effect,
            .sleep(PredicatePollingSleep(duration: SemanticObservationTiming.visibleTickIntervalSeconds))
        )

        let matched = reducer.reduce(
            discovery.state,
            event: .discoveryObserved(
                PredicatePollingDiscoveryObservation(sequence: 1, matched: true),
                timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0)
            )
        )
        let expectedMatchedState = PredicatePollingReducer(timeout: 0, pollWhenTimeoutZero: false)
            .start(
                scope: .discovery,
                initialObservedSequence: 1,
                initialVisibleFingerprint: .known("visible-seed")
            )
            .state

        XCTAssertEqual(matched.state, expectedMatchedState)
        XCTAssertEqual(matched.effect, .finish(.matched))
    }

    func testSleepEventsResumeTimeoutOrCancel() {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let discovery = awaitingDiscoveryReduction(reducer)
        let sleeping = reducer.reduce(
            discovery.state,
            event: .discoveryObserved(
                PredicatePollingDiscoveryObservation(sequence: 1, matched: false),
                timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0)
            )
        )
        let resumed = reducer.reduce(sleeping.state, event: .sleepCompleted(remaining: 0.8))
        let expectedResumed = reducer.start(
            scope: .discovery,
            initialObservedSequence: 1,
            initialVisibleFingerprint: .known("visible-seed"),
            discoveryBootstrap: .afterInitialDiscoveryAttempt
        )

        XCTAssertEqual(resumed.state, expectedResumed.state)
        XCTAssertEqual(resumed.effect, expectedResumed.effect)

        let timedOut = reducer.reduce(sleeping.state, event: .sleepCompleted(remaining: 0))
        let cancelled = reducer.reduce(sleeping.state, event: .sleepCancelled)

        XCTAssertEqual(timedOut.state, cancelled.state)
        XCTAssertEqual(timedOut.effect, .finish(.timedOut))
        XCTAssertEqual(cancelled.effect, .finish(.cancelled))
    }

    func testTimeoutZeroPollsOnce() {
        let reducer = PredicatePollingReducer(timeout: 0, pollWhenTimeoutZero: true)
        let started = reducer.start(scope: .visible, initialObservedSequence: 8)
        let timedOut = reducer.reduce(
            started.state,
            event: .visibleUnavailable(timing: PredicatePollingTickTiming(remaining: 0, elapsed: 0))
        )
        let expectedFinishedState = PredicatePollingReducer(timeout: 0, pollWhenTimeoutZero: false)
            .start(scope: .visible, initialObservedSequence: 8)
            .state

        XCTAssertEqual(started.effect, .observe(.visibleImmediate(after: 8)))
        XCTAssertEqual(timedOut.state, expectedFinishedState)
        XCTAssertEqual(timedOut.effect, .finish(.timedOut))
    }

    private func awaitingDiscoveryReduction(
        _ reducer: PredicatePollingReducer
    ) -> PredicatePollingReduction {
        let started = reducer.start(
            scope: .discovery,
            initialObservedSequence: nil,
            initialVisibleFingerprint: .known("visible-seed")
        )
        return reducer.reduce(
            started.state,
            event: .visibleUnavailable(timing: PredicatePollingTickTiming(remaining: 1, elapsed: 0))
        )
    }
}
#endif // canImport(UIKit)
