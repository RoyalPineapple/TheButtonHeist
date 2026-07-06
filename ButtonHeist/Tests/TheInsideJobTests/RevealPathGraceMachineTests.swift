#if canImport(UIKit)
import ButtonHeistSupport
import XCTest

@testable import TheInsideJob

final class RevealPathGraceMachineTests: XCTestCase {
    private let machine = RevealPathGraceMachine(silentReparseInterval: 0.15)

    func testStartTransitionsAreTableDrivenByRemainingTime() {
        struct StartCase {
            let name: String
            let remaining: Double
            let expected: RevealPathGraceTransition
        }

        let initialCursor = cursor(4)
        let context = RevealPathGraceLoopContext(cursor: initialCursor, knownRevealRetry: .available)
        let cases = [
            StartCase(
                name: "uses silent cadence while time remains",
                remaining: 1.0,
                expected: .changed(
                    to: .waitingForTransition(context),
                    effects: [.waitForTransitionEvent(after: initialCursor, timeout: 0.15)]
                )
            ),
            StartCase(
                name: "caps wait to remaining time",
                remaining: 0.05,
                expected: .changed(
                    to: .waitingForTransition(context),
                    effects: [.waitForTransitionEvent(after: initialCursor, timeout: 0.05)]
                )
            ),
            StartCase(
                name: "times out immediately when window expired",
                remaining: 0,
                expected: .changed(to: .finished, effects: [.finish(.timedOut)])
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(
                machine.advance(.idle, with: .begin(cursor: initialCursor, remaining: testCase.remaining)),
                testCase.expected,
                testCase.name
            )
        }
    }

    func testNotificationWakeupThenVisibleResolutionReachesTerminalEffect() {
        var driver = StateDriver(initial: RevealPathGraceState.idle, machine: machine)

        XCTAssertEqual(
            driver.send(.begin(cursor: cursor(1), remaining: 1)).revealPathGraceEffect,
            .waitForTransitionEvent(after: cursor(1), timeout: 0.15)
        )
        XCTAssertEqual(
            driver.send(.transitionWaitCompleted(cursor(8))).revealPathGraceEffect,
            .yieldRealFrame
        )
        XCTAssertEqual(driver.send(.frameYielded).revealPathGraceEffect, .refreshVisibleTree)
        XCTAssertEqual(
            driver.send(.visibleTreeRefreshCompleted(.refreshed, remaining: 0.8)).revealPathGraceEffect,
            .resolveVisibleTarget
        )
        XCTAssertEqual(
            driver.send(.visibleTargetResolved).revealPathGraceEffect,
            .finish(.resolvedVisible)
        )
        XCTAssertEqual(driver.state, .finished)
    }

    func testKnownTargetRevealRetryIsConsumedOnlyOnce() {
        var driver = StateDriver(initial: RevealPathGraceState.idle, machine: machine)

        XCTAssertEqual(
            driver.send(.begin(cursor: cursor(2), remaining: 1)).revealPathGraceEffect,
            .waitForTransitionEvent(after: cursor(2), timeout: 0.15)
        )
        XCTAssertEqual(driver.send(.transitionWaitCompleted(nil)).revealPathGraceEffect, .yieldRealFrame)
        XCTAssertEqual(driver.send(.frameYielded).revealPathGraceEffect, .refreshVisibleTree)
        XCTAssertEqual(
            driver.send(.visibleTreeRefreshCompleted(.refreshed, remaining: 0.9)).revealPathGraceEffect,
            .resolveVisibleTarget
        )
        XCTAssertEqual(
            driver.send(.visibleTargetMissing(remaining: 0.9)).revealPathGraceEffect,
            .attemptKnownTargetReveal
        )
        XCTAssertEqual(
            driver.send(.knownTargetRevealAttempted(.failed, remaining: 0.7)).revealPathGraceEffect,
            .waitForTransitionEvent(after: cursor(2), timeout: 0.15)
        )

        XCTAssertEqual(driver.send(.transitionWaitCompleted(nil)).revealPathGraceEffect, .yieldRealFrame)
        XCTAssertEqual(driver.send(.frameYielded).revealPathGraceEffect, .refreshVisibleTree)
        XCTAssertEqual(
            driver.send(.visibleTreeRefreshCompleted(.refreshed, remaining: 0.6)).revealPathGraceEffect,
            .resolveVisibleTarget
        )
        XCTAssertEqual(
            driver.send(.visibleTargetMissing(remaining: 0.6)).revealPathGraceEffect,
            .waitForTransitionEvent(after: cursor(2), timeout: 0.15)
        )
    }

    func testKnownTargetRevealSuccessFinishesWithDidRevealPayload() {
        var driver = StateDriver(initial: RevealPathGraceState.idle, machine: machine)

        _ = driver.send(.begin(cursor: cursor(3), remaining: 1))
        _ = driver.send(.transitionWaitCompleted(nil))
        _ = driver.send(.frameYielded)
        _ = driver.send(.visibleTreeRefreshCompleted(.refreshed, remaining: 0.9))
        _ = driver.send(.visibleTargetMissing(remaining: 0.9))

        XCTAssertEqual(
            driver.send(.knownTargetRevealAttempted(.revealed(didReveal: true), remaining: 0.8)).revealPathGraceEffect,
            .finish(.resolvedAfterKnownReveal(didReveal: true))
        )
        XCTAssertEqual(driver.state, .finished)
    }

    func testUnavailableVisibleRefreshWaitsUntilGraceWindowExpires() {
        var driver = StateDriver(initial: RevealPathGraceState.idle, machine: machine)

        _ = driver.send(.begin(cursor: cursor(4), remaining: 1))
        _ = driver.send(.transitionWaitCompleted(nil))
        _ = driver.send(.frameYielded)

        XCTAssertEqual(
            driver.send(.visibleTreeRefreshCompleted(.unavailable, remaining: 0.4)).revealPathGraceEffect,
            .waitForTransitionEvent(after: cursor(4), timeout: 0.15)
        )

        _ = driver.send(.transitionWaitCompleted(nil))
        _ = driver.send(.frameYielded)

        XCTAssertEqual(
            driver.send(.visibleTreeRefreshCompleted(.unavailable, remaining: 0)).revealPathGraceEffect,
            .finish(.timedOut)
        )
    }

    func testCancellationFromActiveStatesFinishesAsCancelled() {
        let context = RevealPathGraceLoopContext(cursor: cursor(1), knownRevealRetry: .available)
        let cases: [(String, RevealPathGraceState)] = [
            ("idle", .idle),
            ("waiting", .waitingForTransition(context)),
            ("yielding", .yieldingFrame(context)),
            ("refreshing", .refreshingVisibleTree(context)),
            ("resolving", .resolvingVisibleTarget(context)),
            ("attempting reveal", .attemptingKnownTargetReveal(context.spendKnownRevealRetry())),
        ]

        for (name, state) in cases {
            XCTAssertEqual(
                machine.advance(state, with: .cancelled),
                .changed(to: .finished, effects: [.finish(.cancelled)]),
                name
            )
        }
    }

    func testInvalidTransitionsAreRejectedWithoutChangingState() {
        struct RejectionCase {
            let name: String
            let state: RevealPathGraceState
            let event: RevealPathGraceEvent
            let rejection: RevealPathGraceRejection
        }

        let context = RevealPathGraceLoopContext(cursor: cursor(1), knownRevealRetry: .available)
        let cases = [
            RejectionCase(
                name: "frame yield before wait",
                state: .idle,
                event: .frameYielded,
                rejection: .invalidTransition
            ),
            RejectionCase(
                name: "visible resolution before refresh",
                state: .waitingForTransition(context),
                event: .visibleTargetResolved,
                rejection: .invalidTransition
            ),
            RejectionCase(
                name: "events after terminal state",
                state: .finished,
                event: .cancelled,
                rejection: .alreadyFinished
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(
                machine.advance(testCase.state, with: testCase.event),
                .rejected(testCase.rejection, stayingIn: testCase.state),
                testCase.name
            )
        }
    }

    private func cursor(_ sequence: UInt64) -> AccessibilityNotificationCursor {
        AccessibilityNotificationCursor(sequence: sequence)
    }
}

#endif // canImport(UIKit)
