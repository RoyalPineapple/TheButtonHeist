#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import TheInsideJob
@testable import ThePlans
@testable import TheScore

@MainActor
final class SettlementResultProjectionTests: SemanticObservationStreamTestCase {
    func testTimeoutMatrixProjectsIndependentReadinessPredicateAndHandoffFacts() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commit(label: "Observed")
        let predicate = transitionPredicate()

        let readyUnmet = await result(
            baseline: baseline,
            observed: observed,
            predicate: predicate,
            predicateMet: false,
            readiness: .established(readiness(at: observed)),
            handoff: await admittedHandoff(observed, baseline: baseline),
            outcome: .timedOut
        )
        let metNotReady = await result(
            baseline: baseline,
            observed: observed,
            predicate: predicate,
            predicateMet: true,
            readiness: .pending(.initial),
            handoff: .pending(.initial),
            outcome: .timedOut
        )
        let metReadyNoHandoff = await result(
            baseline: baseline,
            observed: observed,
            predicate: predicate,
            predicateMet: true,
            readiness: .established(readiness(at: observed)),
            handoff: .captureRequested(.init(
                scope: .visible,
                readinessGeneration: .initial
            )),
            outcome: .timedOut
        )

        let rows = [
            (readyUnmet, false, true, true),
            (metNotReady, true, false, false),
            (metReadyNoHandoff, true, true, false),
        ]
        for (result, predicateMet, readinessEstablished, handoffCompleted) in rows {
            let projection = Settlement.ResultProjector.projectWait(result)
            let settlement = try XCTUnwrap(projection.actionResult.evidence.settlement)
            XCTAssertEqual(projection.expectation.met, predicateMet)
            XCTAssertEqual(settlement.readinessEstablished, readinessEstablished)
            XCTAssertEqual(settlement.observationHandoffCompleted, handoffCompleted)
        }
        XCTAssertEqual(
            metReadyNoHandoff.evidence.readiness.isEstablished,
            true
        )
        XCTAssertEqual(
            Settlement.ResultProjector.projectWait(metReadyNoHandoff).actionResult.evidence.settlement,
            .observationHandoffTimedOut(duration: 25, path: .uikitIdle)
        )
    }

    func testActionProjectionKeepsDispatchFailurePredicateNotEvaluated() async {
        let baseline = await commit(label: "Baseline")
        let predicate = transitionPredicate()
        var predicateEvidence = Settlement.Predicate.Evidence(predicate: predicate)
        predicateEvidence.recordDispatchFailure()
        let command = Settlement.Command(
            trigger: .action(.dismiss),
            predicate: predicate,
            deadline: .init(instant: .now)
        )
        let result = Settlement.Result(
            outcome: .dispatchFailed,
            evidence: Settlement.Evidence(
                command: command,
                boundary: .established(.init(moment: baseline.moment)),
                trigger: .actionDispatched(.failure(.dismiss, message: "dismiss failed")),
                predicate: predicateEvidence,
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                observationHistory: .events([]),
                deadline: .init(deadline: command.deadline, elapsed: 4, reached: false)
            )
        )

        let projection = Settlement.ResultProjector.projectAction(result)

        XCTAssertNil(projection.checkedExpectation)
        XCTAssertEqual(projection.dispatchResult?.outcome, .failure(.actionFailed))
    }

    func testActionPendingAtDeadlineProjectsDispatchTimeoutAndPreservesDiagnosis() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commit(label: "Observed")
        let predicate = transitionPredicate()
        let command = Settlement.Command(
            trigger: .action(.dismiss),
            predicate: predicate,
            deadline: .init(instant: .now)
        )
        let result = Settlement.Result(
            outcome: .timedOut,
            evidence: Settlement.Evidence(
                command: command,
                boundary: .established(.init(moment: baseline.moment)),
                trigger: .actionPending(.dismiss),
                predicate: Settlement.Predicate.Evidence(predicate: predicate),
                readiness: .established(readiness(at: observed)),
                handoff: .captureRequested(.init(
                    scope: .visible,
                    readinessGeneration: .initial
                )),
                observationHistory: await history(after: baseline),
                deadline: .init(deadline: command.deadline, elapsed: 25, reached: true)
            )
        )

        let projection = Settlement.ResultProjector.projectAction(result)
        let dispatch = try XCTUnwrap(projection.dispatchResult)
        let settlement = try XCTUnwrap(dispatch.evidence.settlement)
        let diagnosis = Settlement.Diagnosis.project(result)

        XCTAssertEqual(dispatch.outcome, .failure(.timeout))
        XCTAssertEqual(
            dispatch.message,
            "action dispatch did not complete before settlement deadline after 25ms"
        )
        XCTAssertEqual(settlement, .observationHandoffTimedOut(duration: 25, path: .uikitIdle))
        XCTAssertEqual(projection.checkedExpectation?.met, false)
        XCTAssertEqual(diagnosis.dispatch, .pending)
        XCTAssertEqual(diagnosis.readiness, .established(generation: .initial, path: .uikitIdle))
        XCTAssertEqual(diagnosis.handoff, .captureRequested(generation: .initial))
        XCTAssertEqual(diagnosis.outcome, .timedOut)
        XCTAssertTrue(diagnosis.deadline.reached)
    }

    func testWaitTimeoutProjectsCandidatesFromTerminalSettlementTrace() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commit(label: "Ticket saved., Dismiss")
        let authored = AccessibilityPredicate.exists(.label("Ticket saved."))
        let predicate = Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
        let settlement = await result(
            baseline: baseline,
            observed: observed,
            predicate: predicate,
            predicateMet: false,
            readiness: .established(readiness(at: observed)),
            handoff: await admittedHandoff(observed, baseline: baseline),
            outcome: .timedOut
        )

        let message = try XCTUnwrap(
            Settlement.ResultProjector.projectWait(settlement).actionResult.message
        )

        XCTAssertTrue(message.contains("waiting for element to appear"), message)
        XCTAssertTrue(message.contains(#"expected: label="Ticket saved.""#), message)
        XCTAssertTrue(message.contains("interface: 1 elements"), message)
        XCTAssertTrue(message.contains("last result: element not found"), message)
        XCTAssertTrue(message.contains("Next: get_interface()"), message)
        XCTAssertTrue(
            message.contains(#"observed accessibility candidate label="Ticket saved., Dismiss""#),
            message
        )
        XCTAssertTrue(
            message.contains(#"did not match exists(target(predicate(label="Ticket saved.")))"#),
            message
        )
    }

    func testWaitTimeoutWithSatisfiedPredicateExplainsReadinessWithoutMismatchCandidates() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commit(label: "Ready")
        let authored = AccessibilityPredicate.exists(.label("Ready"))
        let predicate = Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
        let settlement = await result(
            baseline: baseline,
            observed: observed,
            predicate: predicate,
            predicateMet: true,
            readiness: .pending(.initial),
            handoff: .pending(.initial),
            outcome: .timedOut
        )

        let message = try XCTUnwrap(
            Settlement.ResultProjector.projectWait(settlement).actionResult.message
        )

        XCTAssertTrue(message.contains("predicate was satisfied"), message)
        XCTAssertTrue(message.contains("interface readiness did not complete"), message)
        XCTAssertFalse(message.contains("observed accessibility candidate"), message)
        XCTAssertFalse(message.contains("did not match"), message)
    }

    func testSuccessfulExistsWaitProjectsMatchedMessageAndKeepsActualEvidence() async throws {
        let projection = try await successfulWaitProjection(
            predicate: .exists(.label("Ready")),
            observedLabel: "Ready",
            elapsed: 25
        )

        XCTAssertEqual(projection.actionResult.message, "matched after 0.0s")
        XCTAssertEqual(projection.expectation.actual, "matched")
    }

    func testSuccessfulMissingWaitProjectsAbsentMessageAndKeepsActualEvidence() async throws {
        let projection = try await successfulWaitProjection(
            predicate: .missing(.label("Never Present")),
            observedLabel: "Unrelated",
            elapsed: 25
        )

        XCTAssertEqual(projection.actionResult.message, "absent confirmed after 0.0s")
        XCTAssertEqual(projection.expectation.actual, "matched")
    }

    func testSuccessfulDelayedWaitProjectsElapsedMatchedMessageAndKeepsActualEvidence() async throws {
        let projection = try await successfulWaitProjection(
            predicate: .exists(.label("Delayed")),
            observedLabel: "Delayed",
            elapsed: 1_500
        )

        XCTAssertEqual(projection.actionResult.message, "matched after 1.5s")
        XCTAssertEqual(projection.expectation.actual, "matched")
    }

    func testSuccessfulIdentifierWaitProjectsMatchedMessageAndKeepsActualEvidence() async throws {
        let projection = try await successfulWaitProjection(
            predicate: .exists(.identifier("save_button")),
            observedLabel: "Save",
            elapsed: 1_000
        )

        XCTAssertEqual(projection.actionResult.message, "matched after 1.0s")
        XCTAssertEqual(projection.expectation.actual, "matched")
    }

    private func result(
        baseline: Observation.SnapshotEvent,
        observed: Observation.SnapshotEvent,
        predicate: Settlement.Predicate,
        predicateMet: Bool,
        readiness: Settlement.Readiness.Evidence,
        handoff: Settlement.Handoff.Evidence,
        outcome: Settlement.Outcome,
        elapsed: ElapsedMilliseconds = 25
    ) async -> Settlement.Result {
        var predicateEvidence = Settlement.Predicate.Evidence(predicate: predicate)
        let request = Settlement.Predicate.EvaluationRequest(
            predicate: predicate,
            target: .observation(observed.moment),
            evidence: predicate.semantics == .currentState
                ? .currentState(observed)
                : .positiveTransition(observed)
        )
        precondition(predicateEvidence.schedule(request))
        predicateEvidence.record(.init(
            target: request.target,
            result: PredicateEvaluationResult(met: predicateMet, actual: predicateMet ? "matched" : "missing")
        ))
        let command = Settlement.Command(
            trigger: .observation,
            predicate: predicate,
            deadline: .init(instant: .now)
        )
        return Settlement.Result(
            outcome: outcome,
            evidence: Settlement.Evidence(
                command: command,
                boundary: .established(.init(moment: baseline.moment)),
                trigger: .observation,
                predicate: predicateEvidence,
                readiness: readiness,
                handoff: handoff,
                observationHistory: await history(after: baseline),
                deadline: .init(deadline: command.deadline, elapsed: elapsed, reached: true)
            )
        )
    }

    private func successfulWaitProjection(
        predicate authored: AccessibilityPredicate,
        observedLabel: String,
        elapsed: ElapsedMilliseconds
    ) async throws -> HeistWaitEvidence {
        let baseline = await commit(label: "Baseline")
        let observed = await commit(label: observedLabel)
        let predicate = Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
        let settlement = await result(
            baseline: baseline,
            observed: observed,
            predicate: predicate,
            predicateMet: true,
            readiness: .established(readiness(at: observed)),
            handoff: await admittedHandoff(observed, baseline: baseline),
            outcome: .settled,
            elapsed: elapsed
        )
        return Settlement.ResultProjector.projectWait(settlement)
    }

    private func transitionPredicate() -> Settlement.Predicate {
        Settlement.Predicate(
            authored: .changed(.elements()),
            resolved: ResolvedAccessibilityPredicate(core: .changed(.elements([])))
        )
    }

    private func readiness(
        at event: Observation.SnapshotEvent
    ) -> Settlement.Readiness.Establishment {
        Settlement.Readiness.Establishment(
            generation: .initial,
            path: .uikitIdle,
            observationBoundary: .including(event.moment)
        )
    }

    private func admittedHandoff(
        _ event: Observation.SnapshotEvent,
        baseline: Observation.SnapshotEvent
    ) async -> Settlement.Handoff.Evidence {
        let admission = Settlement.ObservationAdmission(
            event: event,
            history: await history(after: baseline)
        )
        guard let handoff = Settlement.Handoff.Admission.admit(
            admission,
            for: readiness(at: event)
        ) else {
            preconditionFailure("Test handoff must be eligible")
        }
        return .admitted(handoff)
    }

    private func history(after baseline: Observation.SnapshotEvent) async -> Observation.EventsSince {
        await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: baseline.moment)
        }
    }

    private func commit(label: String) async -> Observation.SnapshotEvent {
        await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: label, heistId: HeistId(rawValue: label.lowercased()))
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
