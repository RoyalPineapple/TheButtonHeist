#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

import ButtonHeistTestSupport
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import ThePlans
@testable import TheScore

@MainActor
final class SettlementReducerTests: SemanticObservationStreamTestCase {
    func testCurrentStateCaptureCompletesWithExactEventWithoutArming() async throws {
        let current = await commit(label: "Current")
        var decision = Settlement.Reducer.begin(.currentState(scope: .visible))

        XCTAssertEqual(decision.effects.filter(\.capturesBaseline).count, 1)
        decision = reduce(decision, .baselineAdmitted(current))

        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected one current-state capture to complete")
        }
        guard case .currentState(.captured(let capture)) = result else {
            return XCTFail("Expected captured current state")
        }
        XCTAssertEqual(capture.event, current)
        XCTAssertFalse(decision.effects.contains(where: \.armsChannels))
    }

    func testPredicateSemanticsAreDerivedFromResolvedCore() async throws {
        let target = AccessibilityTarget.predicate(ElementPredicate(label: "Save"))
        let authored = [
            AccessibilityPredicate.exists(target),
            .elementsChanged([.appeared(target)]),
            .announcement("Saved"),
        ]
        let environment = HeistExecutionEnvironment()

        let semantics = try authored.map {
            Settlement.Predicate(
                authored: $0,
                resolved: try $0.resolve(in: environment)
            ).semantics
        }

        // One semantics per authored predicate, read off its resolved core.
        XCTAssertEqual(semantics, [
            .currentState,
            .positiveTransition,
            .announcement,
        ])
    }

    func testSuppliedBaselineArmsWithoutCapturingAnotherBaseline() async {
        let baseline = await commit(label: "Baseline")
        let boundary = Settlement.EvidenceBoundary(moment: baseline.moment)
        let command = Settlement.Command.observation(
            predicate: transitionPredicate(),
            deadline: deadline,
            baseline: .supplied(boundary)
        )

        let decision = Settlement.Reducer.begin(command)

        guard case .armed(let session) = decision.state else {
            return XCTFail("Expected the supplied evidence boundary to arm Settlement")
        }
        XCTAssertEqual(session.boundary, boundary)
        XCTAssertFalse(decision.effects.contains(where: \.capturesBaseline))
        XCTAssertEqual(decision.effects.filter(\.armsChannels).count, 1)
    }

    func testUnavailableSuppliedBaselineTerminatesWithoutArmingOrCapture() {
        let command = Settlement.Command.observation(
            predicate: transitionPredicate(),
            deadline: deadline,
            baseline: .unavailable(.unavailable)
        )

        let decision = Settlement.Reducer.begin(command)

        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected unavailable supplied evidence to fail before arming")
        }
        guard case .observation(.failed(let failed)) = result else {
            return XCTFail("Expected unavailable observation baseline")
        }
        XCTAssertEqual(failed.reason, .baselineUnavailable)
        XCTAssertEqual(failed.attempt.boundary, .unavailable(.unavailable))
        XCTAssertFalse(decision.effects.contains(where: \.capturesBaseline))
        XCTAssertFalse(decision.effects.contains(where: \.armsChannels))
    }

    func testArmedAndActiveTerminalCausesEnterFinalizationWithoutResult() async {
        let baseline = await commit(label: "Baseline")
        var armed = Settlement.Reducer.begin(.observation(
            predicate: transitionPredicate(),
            deadline: deadline,
            baseline: .capture
        ))
        armed = reduce(armed, .baselineAdmitted(baseline))
        let active = reduce(armed, .channelsArmed)

        for (name, decision) in [
            ("armed", reduce(armed, .cancelled)),
            ("active", reduce(active, .cancelled)),
        ] {
            assertFinalizing(decision, name)
        }
    }

    func testViewportExitFinalizesOrReplacesTheIntendedOutcome() async {
        let baseline = await commit(label: "Baseline")
        let handoff = await commitSettling(label: "Handoff")
        var settled = armedPredicateFreeActionDecision(baseline: baseline)
        settled = reduce(
            settled,
            .observationAdmitted(admission(handoff.changed))
        )
        settled = reduce(
            settled,
            .observationAdmitted(admission(handoff.settled))
        )
        settled = reduce(
            settled,
            .readinessEstablished(.init(
                generation: .initial,
                observationBoundary: .including(handoff.settled.moment)
            ))
        )

        for viewportExit in [
            Navigation.ViewportExit.Outcome.restored,
            .retained,
            .superseded,
        ] {
            let decision = reduce(settled, .finalized(viewportExit))
            guard case .terminal(.action(.settled)) = decision.state else {
                return XCTFail("Expected \(viewportExit) to preserve settled action")
            }
            XCTAssertTrue(decision.effects.isEmpty)
        }

        var timedOut = armedObservationDecision(
            baseline: baseline,
            predicate: transitionPredicate()
        )
        timedOut = reduce(timedOut, .deadlineReached(deadline))
        for (name, intended) in [
            ("settled", settled),
            ("timed out", timedOut),
        ] {
            let decision = reduce(
                intended,
                .finalized(.failed(.originUnavailable))
            )
            guard case .terminal(let result) = decision.state else {
                return XCTFail("Expected failed viewport exit to terminalize \(name)")
            }
            switch result {
            case .action(.failed(let failed)):
                XCTAssertEqual(failed.reason, .viewportExitFailed(.originUnavailable), name)
            case .observation(.failed(let failed)):
                XCTAssertEqual(failed.reason, .viewportExitFailed(.originUnavailable), name)
            case .currentState, .action(.settled), .observation(.settled):
                XCTFail("Expected failed viewport exit to replace \(name)")
            }
            XCTAssertTrue(decision.effects.isEmpty, name)
        }
    }
    func testTerminalStateEmitsNoFurtherEffects() async {
        let baseline = await commit(label: "Baseline")
        var decision = armedPredicateFreeActionDecision(baseline: baseline)
        let ready = await commitSettling(label: "Ready")
        decision = reduce(decision, .observationAdmitted(admission(ready.changed)))
        decision = reduce(decision, .observationAdmitted(admission(ready.settled)))
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                observationBoundary: .including(ready.changed.moment)
            ))
        )
        guard let finalized = completeFinalization(decision) else { return }
        decision = finalized
        guard case .terminal(.action(.settled(let result))) = decision.state else {
            return XCTFail("Expected settled action")
        }
        let handoffMoment = result.handoff.event.moment

        decision = reduce(
            decision,
            .deadlineReached(.init(
                phase: .actionReadiness,
                instant: RuntimeElapsed.now
            ))
        )

        guard case .terminal(.action(.settled(let unchanged))) = decision.state else {
            return XCTFail("Expected terminal result to remain settled")
        }
        XCTAssertEqual(unchanged.handoff.event.moment, handoffMoment)
        XCTAssertTrue(decision.effects.isEmpty)
    }
    func testStaleGenerationHandoffAdmissionCannotCompleteSettlement() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedPredicateFreeActionDecision(baseline: baseline)
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                observationBoundary: .after(baseline.moment)
            ))
        )
        decision = reduce(decision, .readinessInvalidated(.initial.advanced()))
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial.advanced(),
                observationBoundary: .after(baseline.moment)
            ))
        )

        let stale = await commit(label: "Stale")
        decision = reduce(
            decision,
            .observationAdmitted(admission(
                stale,
                source: .handoffCapture(.initial)
            ))
        )
        XCTAssertNil(decision.state.result)
        XCTAssertNil(try activeSession(in: decision).handoff.event)

        let current = await commitSettling(label: "Current")
        decision = reduce(
            decision,
            .observationAdmitted(admission(
                current.changed,
                source: .handoffCapture(.initial.advanced())
            ))
        )
        // The quiet reading that follows lets the run settle without displacing
        // the handoff, which belongs to the generation that captured it.
        decision = reduce(decision, .observationAdmitted(admission(current.settled)))

        guard let finalized = completeFinalization(decision) else { return }
        decision = finalized
        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected only the active readiness generation to admit a handoff")
        }
        guard case .action(.settled(let settled)) = result else {
            return XCTFail("Expected settled action")
        }
        XCTAssertEqual(settled.handoff.event.moment, current.changed.moment)
        XCTAssertEqual(settled.handoff.generation, .initial.advanced())
    }
    func testHandoffCaptureFailureRemainsDistinctFromReadiness() async {
        let baseline = await commit(label: "Baseline")
        var decision = armedPredicateFreeActionDecision(baseline: baseline)
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                observationBoundary: .after(baseline.moment)
            ))
        )
        decision = reduce(
            decision,
            .handoffCaptureFailed(.initial, .admissionRejected)
        )
        guard let session = try? activeSession(in: decision),
              case .actionReadiness(let deadline) = session.phase else {
            return XCTFail("Expected action readiness deadline")
        }
        decision = reduce(
            decision,
            .deadlineReached(.init(
                phase: deadline.phase,
                instant: deadline.instant
            ))
        )

        guard let finalized = completeFinalization(decision) else { return }
        decision = finalized
        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected failed handoff capture to time out")
        }
        guard case .action(.failed(let failed)) = result else {
            return XCTFail("Expected failed action")
        }
        XCTAssertEqual(failed.reason, .timedOut(.actionReadiness))
        XCTAssertTrue(failed.attempt.readiness.isEstablished)
        XCTAssertEqual(
            failed.attempt.handoff,
            .captureFailed(.initial, .admissionRejected)
        )
    }

    func testActionReadinessDeadlineIgnoresExpectationTimeout() async {
        let baseline = await commit(label: "Baseline")
        let dispatchAt = ContinuousClock.now
        let rows: [Duration?] = [
            nil,
            .milliseconds(1_000),
            .milliseconds(5_000),
            .milliseconds(8_000),
        ]

        for expectationAllowance in rows {
            let predicate = expectationAllowance == nil ? nil : transitionPredicate()
            let action = Settlement.Command.Action(
                command: .dismiss,
                predicate: predicate,
                allowances: .init(
                    readiness: .milliseconds(5_000),
                    expectation: expectationAllowance
                ),
                baseline: .capture
            )
            var decision = armedDecision(
                command: .action(action),
                baseline: baseline
            )
            decision = reduce(
                decision,
                .dispatchCompleted(.success(payload: .dismiss)),
                elapsed: 0,
                instant: dispatchAt
            )

            XCTAssertEqual(
                decision.effects.phaseDeadline,
                Settlement.PhaseDeadline(
                    phase: .actionReadiness,
                    instant: dispatchAt.advanced(by: action.allowances.readiness)
                ),
                "expectation allowance \(String(describing: expectationAllowance))"
            )
        }
    }

    func testPendingAnnouncementArmsExpectationDeadlineOnceAtFirstReadyHandoff() async throws {
        let baseline = await commit(label: "Baseline")
        let ready = await commit(label: "Ready")
        let nextReady = await commit(label: "Next Ready")
        let dispatchAt = ContinuousClock.now
        let readyAt = dispatchAt.advanced(by: .milliseconds(3_200))
        let deadline = Settlement.PhaseDeadline(
            phase: .actionExpectation,
            instant: readyAt.advanced(by: .milliseconds(1_000))
        )
        var decision = try await actionAwaitingEvidence(
            baseline: baseline,
            ready: ready,
            dispatchAt: dispatchAt,
            readyAt: readyAt,
            predicate: try announcementPredicate()
        )

        XCTAssertEqual(decision.effects.phaseDeadline, deadline)

        decision = reduce(
            decision,
            .readinessInvalidated(.initial.advanced()),
            elapsed: 3_500
        )
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial.advanced(),
                observationBoundary: .including(nextReady.moment)
            )),
            elapsed: 3_500
        )
        decision = reduce(
            decision,
            .observationAdmitted(admission(
                nextReady,
                source: .handoffCapture(.initial.advanced()),
                instant: dispatchAt.advanced(by: .milliseconds(3_500))
            )),
            elapsed: 3_500
        )

        XCTAssertNil(decision.state.result)
        XCTAssertNil(decision.effects.phaseDeadline)
        XCTAssertEqual(try activeSession(in: decision).phase, .actionExpectation(deadline))
    }

    func testStaleReadinessDeadlineIsIgnoredInExpectationPhase() async throws {
        let baseline = await commit(label: "Baseline")
        let ready = await commit(label: "Ready")
        let dispatchAt = ContinuousClock.now
        let staleDeadline = Settlement.PhaseDeadline(
            phase: .actionReadiness,
            instant: dispatchAt.advanced(by: .milliseconds(5_000))
        )
        var decision = try await actionAwaitingEvidence(
            baseline: baseline,
            ready: ready,
            dispatchAt: dispatchAt,
            readyAt: dispatchAt.advanced(by: .milliseconds(3_200)),
            predicate: transitionPredicate()
        )

        decision = reduce(
            decision,
            .deadlineReached(staleDeadline),
            elapsed: 5_000,
            instant: staleDeadline.instant
        )

        XCTAssertNil(decision.state.result)
        XCTAssertTrue(decision.effects.isEmpty)
    }

    private lazy var deadline = Settlement.PhaseDeadline(
        phase: .observation,
        instant: ContinuousClock.now.advanced(by: .seconds(1))
    )

    private func transitionPredicate() -> Settlement.Predicate {
        Settlement.Predicate(
            authored: .elementsChanged,
            resolved: .elementsChanged([])
        )
    }

    private func currentStatePredicate() throws -> Settlement.Predicate {
        let authored = AccessibilityPredicate.exists(
            .predicate(ElementPredicate(label: "Save"))
        )
        return Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
    }

    private func announcementPredicate() throws -> Settlement.Predicate {
        let authored = AccessibilityPredicate.announcement("Saved")
        return Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
    }

    private func armedObservationDecision(
        baseline: Observation.SnapshotEvent,
        predicate: Settlement.Predicate
    ) -> Settlement.Decision {
        var decision = Settlement.Reducer.begin(.observation(
            predicate: predicate,
            deadline: deadline,
            baseline: .capture
        ))
        decision = reduce(
            decision,
            .baselineAdmitted(baseline)
        )
        return reduce(decision, .channelsArmed)
    }

    private func armedDecision(
        command: Settlement.Command,
        baseline: Observation.SnapshotEvent
    ) -> Settlement.Decision {
        var decision = Settlement.Reducer.begin(command)
        decision = reduce(
            decision,
            .baselineAdmitted(baseline)
        )
        return reduce(decision, .channelsArmed)
    }

    private func armedPredicateFreeActionDecision(
        baseline: Observation.SnapshotEvent
    ) -> Settlement.Decision {
        var decision = armedDecision(
            command: .action(.init(
                command: .dismiss,
                predicate: nil,
                allowances: .init(readiness: .seconds(5), expectation: nil),
                baseline: .capture
            )),
            baseline: baseline
        )
        decision = reduce(
            decision,
            .dispatchCompleted(.success(payload: .dismiss))
        )
        return decision
    }

    private func actionAwaitingEvidence(
        baseline: Observation.SnapshotEvent,
        ready: Observation.SnapshotEvent,
        dispatchAt: ContinuousClock.Instant,
        readyAt: ContinuousClock.Instant,
        predicate: Settlement.Predicate
    ) async throws -> Settlement.Decision {
        var decision = armedDecision(
            command: .action(.init(
                command: .dismiss,
                predicate: predicate,
                allowances: .init(
                    readiness: .milliseconds(5_000),
                    expectation: .milliseconds(1_000)
                ),
                baseline: .capture
            )),
            baseline: baseline
        )
        decision = reduce(
            decision,
            .dispatchCompleted(.success(payload: .dismiss)),
            elapsed: 0,
            instant: dispatchAt
        )
        let readyElapsed = Int(
            (dispatchAt.duration(to: readyAt) / .milliseconds(1)).rounded()
        )
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                observationBoundary: .including(ready.moment)
            )),
            elapsed: readyElapsed
        )
        decision = reduce(
            decision,
            .observationAdmitted(admission(
                ready,
                source: .handoffCapture(.initial),
                instant: readyAt
            )),
            elapsed: readyElapsed,
            instant: readyAt
        )
        return decision
    }

    /// An admission of `event`'s last moment.
    ///
    /// The event is the whole evidence: nothing is read back out of the store to
    /// corroborate it, so there is no second version of what the run saw. The
    /// vault says which moments the reading was, and a single admission carries
    /// one of them, so this is the moment the reading ends on.
    private func admission(
        _ event: Observation.SnapshotEvent,
        source: Settlement.ObservationAdmissionSource = .observation,
        instant: ContinuousClock.Instant = RuntimeElapsed.now
    ) -> Settlement.ObservationAdmission {
        Settlement.ObservationAdmission(
            tick: event.isChange
                ? .elementsChanged(event.moment.capture)
                : .noChange,
            event: event,
            source: source,
            instant: instant
        )
    }

    private func announcement(sequence: UInt64, text: String) -> Observation.AnnouncementEvent {
        Observation.AnnouncementEvent(announcement: CapturedAnnouncement(
            sequence: sequence,
            text: text,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            kind: .announcement
        ))
    }

    private func activeSession(in decision: Settlement.Decision) throws -> Settlement.Session {
        guard case .active(let session) = decision.state else {
            throw ActiveSessionError.unavailable
        }
        return session
    }

    private func commit(label: String) async -> Observation.SnapshotEvent {
        await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(
                label: label,
                heistId: HeistId(rawValue: label.lowercased())
            )
        )
    }

    private func reduce(
        _ decision: Settlement.Decision,
        _ fact: Settlement.Event.Fact,
        elapsed: Int = 1,
        instant: ContinuousClock.Instant = RuntimeElapsed.now
    ) -> Settlement.Decision {
        Settlement.Reducer.reduce(
            decision.state,
            event: Settlement.Event(
                fact: fact,
                elapsed: RuntimeElapsed.admit(milliseconds: elapsed),
                instant: instant
            )
        )
    }

    /// Drives a finalizing decision to its terminal state.
    ///
    /// Returns `nil` rather than reducing when the decision is not finalizing.
    /// `.finalized` is only legal from `.finalizing`; the reducer traps on it
    /// anywhere else, and `XCTFail` does not stop the caller. Continuing past a
    /// failed precondition would turn one wrong expectation into a
    /// `preconditionFailure` that takes down the test host and reports every
    /// test after it as failed.
    private func completeFinalization(
        _ decision: Settlement.Decision,
        viewportExit: Navigation.ViewportExit.Outcome = .restored
    ) -> Settlement.Decision? {
        guard assertFinalizing(decision) else { return nil }
        return reduce(decision, .finalized(viewportExit))
    }

    @discardableResult
    private func assertFinalizing(
        _ decision: Settlement.Decision,
        _ message: String = ""
    ) -> Bool {
        XCTAssertNil(decision.state.result, message)
        guard case .finalizing = decision.state else {
            XCTFail("Expected Settlement to finalize before terminal state \(message)")
            return false
        }
        XCTAssertEqual(decision.effects.count, 1, message)
        guard case .finalize = decision.effects.first else {
            XCTFail("Expected exactly one finalization effect \(message)")
            return false
        }
        return true
    }
}

private enum ActiveSessionError: Error {
    case unavailable
}

private struct ProductRow: CustomStringConvertible {
    let command: Settlement.Command
    let dispatchCount: Int

    var description: String {
        String(describing: command)
    }
}

private extension Settlement.Effect {
    var armsChannels: Bool {
        guard case .arm = self else { return false }
        return true
    }

    var capturesBaseline: Bool {
        guard case .capture(.baseline) = self else { return false }
        return true
    }

    var isDispatch: Bool {
        guard case .dispatchAction = self else { return false }
        return true
    }

    var isHandoffCapture: Bool {
        guard case .capture(.handoff) = self else { return false }
        return true
    }

}

private extension Array where Element == Settlement.Effect {
    var phaseDeadline: Settlement.PhaseDeadline? {
        lazy.compactMap {
            switch $0 {
            case .armDeadline(let deadline):
                deadline
            case .capture,
                 .arm,
                 .armReadiness,
                 .dispatchAction,
                 .finalize:
                nil
            }
        }.first
    }
}

private extension Observation.EventsSince {
    var events: [Observation.Event] {
        guard case .events(let events) = self else { return [] }
        return events
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
