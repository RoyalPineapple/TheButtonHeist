#if canImport(UIKit)
import XCTest
@testable import TheInsideJob

final class PredicatePollingReducerTests: XCTestCase {
    func testStartProducesVisibleStepOrExplicitlyFinishes() throws {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let started = reducer.start(scope: .visible, initialObservedSequence: 4)
        let visible = try XCTUnwrap(started.immediateVisible)

        XCTAssertEqual(visible.after, 4)

        let skippedReducer = PredicatePollingReducer(timeout: 0, pollWhenTimeoutZero: false)
        let skipped = skippedReducer.start(scope: .discovery, initialObservedSequence: nil)

        XCTAssertEqual(skipped, .finished(.notPolled))
    }

    func testVisibleObservationTransitionsImmediateAndSettledSteps() throws {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let immediate = try XCTUnwrap(
            reducer.start(scope: .visible, initialObservedSequence: nil).immediateVisible
        )
        let settled = PredicatePollingReducer.observe(
            immediate,
            observation: PredicatePollingVisibleObservation(
                sequence: 1,
                fingerprint: .known("visible-a"),
                matched: false
            ),
            timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0.01)
        )
        let settledVisible = try XCTUnwrap(settled.settledVisible)

        XCTAssertEqual(settledVisible.after, 1)
        XCTAssertEqual(settledVisible.timeout, SemanticObservationTiming.visibleTickIntervalSeconds)

        let visibleFallback = PredicatePollingReducer.observe(
            settledVisible,
            observation: nil,
            timing: PredicatePollingTickTiming(remaining: 0.8, elapsed: 0)
        )

        XCTAssertEqual(
            visibleFallback.sleep?.duration,
            SemanticObservationTiming.visibleTickIntervalSeconds
        )

        let matched = PredicatePollingReducer.observe(
            settledVisible,
            observation: PredicatePollingVisibleObservation(
                sequence: 2,
                fingerprint: .known("visible-b"),
                matched: true
            ),
            timing: PredicatePollingTickTiming(remaining: 0.8, elapsed: 0.02)
        )

        XCTAssertEqual(matched, .finished(.matched))
    }

    func testVisibleUnavailabilityTransitionsImmediateAndSettledSteps() throws {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let immediate = try XCTUnwrap(
            reducer.start(scope: .visible, initialObservedSequence: 3).immediateVisible
        )
        let settled = PredicatePollingReducer.observe(
            immediate,
            observation: nil,
            timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0)
        )
        let settledVisible = try XCTUnwrap(settled.settledVisible)

        XCTAssertEqual(settledVisible.after, 3)
        XCTAssertEqual(settledVisible.timeout, SemanticObservationTiming.visibleTickIntervalSeconds)

        let sleeping = PredicatePollingReducer.observe(
            settledVisible,
            observation: nil,
            timing: PredicatePollingTickTiming(remaining: 0.8, elapsed: 0)
        )

        XCTAssertEqual(
            sleeping.sleep?.duration,
            SemanticObservationTiming.visibleTickIntervalSeconds
        )

        let discovery = try awaitingDiscoveryStep(reducer)

        XCTAssertNil(discovery.after)
        XCTAssertEqual(discovery.timeout, 1)
    }

    func testDiscoveryObservationTransitionsToMatchingOrSleeping() throws {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let discovery = try awaitingDiscoveryStep(reducer)
        let observedNoMatch = PredicatePollingReducer.observe(
            discovery,
            observation: PredicatePollingDiscoveryObservation(sequence: 1, matched: false),
            timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0)
        )

        XCTAssertEqual(
            observedNoMatch.sleep?.duration,
            SemanticObservationTiming.visibleTickIntervalSeconds
        )

        let unavailable = PredicatePollingReducer.observe(
            discovery,
            observation: nil,
            timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0)
        )

        XCTAssertEqual(
            unavailable.sleep?.duration,
            SemanticObservationTiming.visibleTickIntervalSeconds
        )

        let observedSleep = try XCTUnwrap(observedNoMatch.sleep)
        let observedImmediate = try XCTUnwrap(
            PredicatePollingReducer.resume(observedSleep, remaining: 0.8).immediateVisible
        )
        let observedContinuation = PredicatePollingReducer.observe(
            observedImmediate,
            observation: nil,
            timing: PredicatePollingTickTiming(remaining: 0.8, elapsed: 0)
        )
        XCTAssertNotNil(observedContinuation.settledVisible)

        let unavailableSleep = try XCTUnwrap(unavailable.sleep)
        let unavailableImmediate = try XCTUnwrap(
            PredicatePollingReducer.resume(unavailableSleep, remaining: 0.8).immediateVisible
        )
        let unavailableContinuation = PredicatePollingReducer.observe(
            unavailableImmediate,
            observation: nil,
            timing: PredicatePollingTickTiming(remaining: 0.8, elapsed: 0)
        )
        XCTAssertNotNil(unavailableContinuation.discovery)

        let matched = PredicatePollingReducer.observe(
            discovery,
            observation: PredicatePollingDiscoveryObservation(sequence: 1, matched: true),
            timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0)
        )

        XCTAssertEqual(matched, .finished(.matched))
    }

    func testSleepStepResumesTimesOutOrCancels() throws {
        let reducer = PredicatePollingReducer(timeout: 1, pollWhenTimeoutZero: true)
        let discovery = try awaitingDiscoveryStep(reducer)
        let sleeping = PredicatePollingReducer.observe(
            discovery,
            observation: PredicatePollingDiscoveryObservation(sequence: 1, matched: false),
            timing: PredicatePollingTickTiming(remaining: 0.9, elapsed: 0)
        )
        let sleep = try XCTUnwrap(sleeping.sleep)
        let resumed = PredicatePollingReducer.resume(sleep, remaining: 0.8)
        let expectedResumed = reducer.start(
            scope: .discovery,
            initialObservedSequence: 1,
            initialVisibleFingerprint: .known("visible-seed"),
            discoveryBootstrap: .afterInitialDiscoveryAttempt
        )

        XCTAssertEqual(resumed, expectedResumed)

        let timedOut = PredicatePollingReducer.resume(sleep, remaining: 0)
        let cancelled = PredicatePollingReducer.resume(sleep, remaining: nil)

        XCTAssertEqual(timedOut, .finished(.timedOut))
        XCTAssertEqual(cancelled, .finished(.cancelled))
    }

    func testTimeoutZeroPollsOnce() throws {
        let reducer = PredicatePollingReducer(timeout: 0, pollWhenTimeoutZero: true)
        let started = reducer.start(scope: .visible, initialObservedSequence: 8)
        let visible = try XCTUnwrap(started.immediateVisible)
        let timedOut = PredicatePollingReducer.observe(
            visible,
            observation: nil,
            timing: PredicatePollingTickTiming(remaining: 0, elapsed: 0)
        )

        XCTAssertEqual(visible.after, 8)
        XCTAssertEqual(timedOut, .finished(.timedOut))
    }

    private func awaitingDiscoveryStep(
        _ reducer: PredicatePollingReducer
    ) throws -> PredicatePollingDiscoveryStep {
        let visible = try XCTUnwrap(reducer.start(
            scope: .discovery,
            initialObservedSequence: nil,
            initialVisibleFingerprint: .known("visible-seed")
        ).immediateVisible)
        return try XCTUnwrap(PredicatePollingReducer.observe(
            visible,
            observation: nil,
            timing: PredicatePollingTickTiming(remaining: 1, elapsed: 0)
        ).discovery)
    }
}

private extension PredicatePollingStep {
    var immediateVisible: PredicatePollingImmediateVisibleStep? {
        guard case .observeImmediateVisible(let step) = self else { return nil }
        return step
    }

    var settledVisible: PredicatePollingSettledVisibleStep? {
        guard case .observeSettledVisible(let step) = self else { return nil }
        return step
    }

    var discovery: PredicatePollingDiscoveryStep? {
        guard case .observeDiscovery(let step) = self else { return nil }
        return step
    }

    var sleep: PredicatePollingSleepStep? {
        guard case .sleep(let step) = self else { return nil }
        return step
    }
}
#endif // canImport(UIKit)
