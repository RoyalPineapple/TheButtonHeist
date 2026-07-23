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
    func testTwoByTwoProductRequiresReadinessAndHandoff() async throws {
        let rows = [
            ProductRow(trigger: .action(.dismiss), hasPredicate: false, dispatchCount: 1),
            ProductRow(trigger: .action(.dismiss), hasPredicate: true, dispatchCount: 1),
            ProductRow(trigger: .observation, hasPredicate: false, dispatchCount: 0),
            ProductRow(trigger: .observation, hasPredicate: true, dispatchCount: 0),
        ]

        for row in rows {
            let baseline = await commit(label: "Baseline")
            let command = Settlement.Command(
                trigger: row.trigger,
                predicate: row.hasPredicate ? transitionPredicate() : nil,
                deadline: deadline
            )
            var decision = Settlement.Reducer.begin(command)
            var dispatchCount = 0

            decision = reduce(
                decision,
                .baselineAdmitted(.init(moment: baseline.moment))
            )
            XCTAssertEqual(decision.effects.count, 1)
            guard case .arm = decision.effects.first else {
                XCTFail("Expected the invocation channels to arm")
                continue
            }

            decision = reduce(decision, .channelsArmed)
            dispatchCount += decision.effects.filter(\.isDispatch).count
            if row.dispatchCount == 1 {
                decision = reduce(
                    decision,
                    .dispatchCompleted(.success(payload: .dismiss))
                )
            }

            decision = reduce(
                decision,
                .readinessEstablished(.init(
                    generation: .initial,
                    path: .uikitIdle,
                    observationBoundary: .after(baseline.moment)
                ))
            )
            XCTAssertNil(decision.state.result)
            XCTAssertEqual(decision.effects.filter(\.isHandoffCapture).count, 1)

            let handoff = await commit(label: "Handoff")
            decision = reduce(decision, .observationAdmitted(await admission(handoff, after: baseline)))
            if let evaluation = decision.effects.compactMap(\.predicateEvaluation).first {
                decision = reduce(
                    decision,
                    .predicateEvaluated(.init(
                        target: evaluation.target,
                        result: PredicateEvaluationResult(met: true)
                    ))
                )
            }

            dispatchCount += decision.effects.filter(\.isDispatch).count
            XCTAssertEqual(dispatchCount, row.dispatchCount)
            guard case .completed(let result) = decision.state else {
                XCTFail("Expected readiness and an admitted handoff to complete \(row)")
                continue
            }
            XCTAssertEqual(result.outcome, .settled)
            XCTAssertEqual(result.evidence.handoff.event?.moment, handoff.moment)
        }
    }

    func testPredicateSemanticsAreDerivedFromResolvedCore() async throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Save"))
        let authored = [
            AccessibilityPredicate.exists(target),
            .changed(.elements([.appeared(target)])),
            .announcement("Saved"),
            .noChange,
        ]
        let environment = HeistExecutionEnvironment()

        let semantics = try authored.map {
            Settlement.Predicate(
                authored: $0,
                resolved: try $0.resolve(in: environment)
            ).semantics
        }

        XCTAssertEqual(semantics, [
            .currentState,
            .positiveTransition,
            .announcement,
            .completeHistory,
        ])
    }

    func testSuppliedBaselineArmsWithoutCapturingAnotherBaseline() async {
        let baseline = await commit(label: "Baseline")
        let boundary = Settlement.EvidenceBoundary(moment: baseline.moment)
        let command = Settlement.Command(
            trigger: .observation,
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
        let command = Settlement.Command(
            trigger: .observation,
            predicate: transitionPredicate(),
            deadline: deadline,
            baseline: .unavailable(.unavailable)
        )

        let decision = Settlement.Reducer.begin(command)

        guard case .failed(let result) = decision.state else {
            return XCTFail("Expected unavailable supplied evidence to fail before arming")
        }
        XCTAssertEqual(result.outcome, .baselineUnavailable)
        XCTAssertEqual(result.evidence.boundary, .unavailable(.unavailable))
        XCTAssertFalse(decision.effects.contains(where: \.capturesBaseline))
        XCTAssertFalse(decision.effects.contains(where: \.armsChannels))
        XCTAssertEqual(decision.effects.filter(\.isFinish).count, 1)
    }

    func testMissingPreTriggerMomentRecapturesOnlyCurrentStatePredicates() throws {
        XCTAssertEqual(
            Settlement.Baseline.beforeTrigger(
                observationMoment: nil,
                predicate: try currentStatePredicate().resolved
            ),
            .capture
        )
        XCTAssertEqual(
            Settlement.Baseline.beforeTrigger(
                observationMoment: nil,
                predicate: transitionPredicate().resolved
            ),
            .unavailable(.unavailable)
        )
        XCTAssertEqual(
            Settlement.Baseline.beforeTrigger(
                observationMoment: nil,
                predicate: try announcementPredicate().resolved
            ),
            .unavailable(.unavailable)
        )
    }

    func testPositiveTransitionEvaluationEventBelongsToRetainedHistory() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(
            baseline: baseline,
            predicate: transitionPredicate()
        )
        let first = await commit(label: "First")
        let second = await commit(label: "Second")

        decision = reduce(
            decision,
            .observationAdmitted(await admission(second, after: baseline))
        )

        let request = try XCTUnwrap(decision.effects.compactMap(\.predicateEvaluation).first)
        guard case .positiveTransition(let evaluatedEvent) = request.evidence,
              case .events(let events) = try activeSession(in: decision).observationHistory else {
            return XCTFail("Expected retained transition history")
        }
        XCTAssertEqual(events, [.snapshot(first), .snapshot(second)])
        XCTAssertEqual(evaluatedEvent, second)
        XCTAssertTrue(events.contains(.snapshot(evaluatedEvent)))
    }

    func testCanonicalPredicateTruthMatrixUsesOnlyPostBaselineLogEvents() async throws {
        let empty = InterfaceObservation.makeForTests()
        let ready = truthObservation(label: "Ready", heistId: "ready")
        let combinedToast = truthObservation(
            label: "Ticket saved., Dismiss",
            heistId: "toast"
        )
        let countOne = truthObservation(label: "Count", value: "1", heistId: "count")
        let countTwo = truthObservation(label: "Count", value: "2", heistId: "count")
        let rows = [
            PredicateTruthRow(
                name: "always-present exists is a level",
                preBaseline: nil,
                baseline: ready,
                observed: ready,
                predicate: .exists(.label("Ready")),
                expected: true
            ),
            PredicateTruthRow(
                name: "always-present does not appear",
                preBaseline: nil,
                baseline: ready,
                observed: ready,
                predicate: .changed(.elements([.appeared(.label("Ready"))])),
                expected: false
            ),
            PredicateTruthRow(
                name: "always-absent missing is a level",
                preBaseline: nil,
                baseline: empty,
                observed: empty,
                predicate: .missing(.label("Ready")),
                expected: true
            ),
            PredicateTruthRow(
                name: "always-absent does not disappear",
                preBaseline: nil,
                baseline: empty,
                observed: empty,
                predicate: .changed(.elements([.disappeared(.label("Ready"))])),
                expected: false
            ),
            PredicateTruthRow(
                name: "semantic value update is a transition",
                preBaseline: nil,
                baseline: countOne,
                observed: countTwo,
                predicate: .changed(.elements([.updated(
                    .label("Count"),
                    .value(before: "1", after: "2")
                )])),
                expected: true
            ),
            PredicateTruthRow(
                name: "exact match is not promoted by a combined label",
                preBaseline: nil,
                baseline: empty,
                observed: combinedToast,
                predicate: .changed(.elements([.appeared(.label("Ticket saved."))])),
                expected: false
            ),
            PredicateTruthRow(
                name: "appearance before the baseline is excluded",
                preBaseline: empty,
                baseline: ready,
                observed: ready,
                predicate: .changed(.elements([.appeared(.label("Ready"))])),
                expected: false
            ),
            PredicateTruthRow(
                name: "complete non-expired fact-free history satisfies noChange",
                preBaseline: nil,
                baseline: ready,
                observed: ready,
                predicate: .noChange,
                expected: true
            ),
        ]

        try await assertTruthRows(rows)
        try await assertTransientHistory(
            empty: empty,
            ready: ready
        )
    }

    private func assertTruthRows(_ rows: [PredicateTruthRow]) async throws {
        for row in rows {
            await vault.semanticObservationStream.storeOwner.reset()
            if let preBaseline = row.preBaseline {
                _ = await vault.semanticObservationStream
                    .commitVisibleObservationForTesting(preBaseline)
            }
            let baseline = await vault.semanticObservationStream
                .commitVisibleObservationForTesting(row.baseline)
            let observed = await vault.semanticObservationStream
                .commitVisibleObservationForTesting(row.observed)
            let history = await vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: baseline.moment)
            }

            guard case .events(let events) = history else {
                XCTFail("Expected direct post-baseline events for \(row.name)")
                continue
            }
            XCTAssertEqual(events, [.snapshot(observed)], row.name)
            let eventsAfterObserved = await vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: observed.moment)
            }
            XCTAssertEqual(
                eventsAfterObserved,
                .events([]),
                row.name
            )
            let result = try await canonicalEvaluation(
                row.predicate,
                event: observed,
                history: history
            )
            XCTAssertEqual(result.met, row.expected, row.name)
        }
    }

    private func assertTransientHistory(
        empty: InterfaceObservation,
        ready: InterfaceObservation
    ) async throws {
        await vault.semanticObservationStream.storeOwner.reset()
        let baseline = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(empty)
        let transient = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(ready)
        let final = await vault.semanticObservationStream
            .commitVisibleObservationForTesting(empty)
        let history = await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: baseline.moment)
        }
        guard case .events(let events) = history else {
            return XCTFail("Expected complete transient history")
        }
        XCTAssertEqual(events, [.snapshot(transient), .snapshot(final)])
        let appeared = try await canonicalEvaluation(
            .changed(.elements([.appeared(.label("Ready"))])),
            event: transient,
            history: history
        )
        let exists = try await canonicalEvaluation(
            .exists(.label("Ready")),
            event: final,
            history: history
        )
        XCTAssertTrue(appeared.met)
        XCTAssertFalse(exists.met)
    }

    func testTransitionEvidenceLatchesAcrossReadinessInvalidation() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(
            baseline: baseline,
            predicate: transitionPredicate()
        )
        let transient = await commit(label: "Transient")
        decision = reduce(decision, .observationAdmitted(await admission(transient, after: baseline)))
        let evaluation = try XCTUnwrap(decision.effects.compactMap(\.predicateEvaluation).first)
        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: evaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )

        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                path: .uikitIdle,
                observationBoundary: .after(transient.moment)
            ))
        )
        XCTAssertEqual(decision.effects.filter(\.isHandoffCapture).count, 1)
        decision = reduce(decision, .readinessInvalidated(.initial.advanced()))
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial.advanced(),
                path: .accessibilityQuietWindow,
                observationBoundary: .after(transient.moment)
            ))
        )
        XCTAssertEqual(decision.effects.filter(\.isHandoffCapture).count, 1)

        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial.advanced(),
                path: .accessibilityQuietWindow,
                observationBoundary: .after(transient.moment)
            ))
        )
        XCTAssertTrue(decision.effects.isEmpty)

        let final = await commit(label: "Final")
        decision = reduce(decision, .observationAdmitted(await admission(final, after: baseline)))
        guard case .completed(let result) = decision.state else {
            return XCTFail("Expected the latched transition to survive readiness invalidation")
        }
        XCTAssertEqual(result.evidence.predicate.satisfiedTarget, evaluation.target)
        XCTAssertEqual(result.evidence.handoff.event?.moment, final.moment)
    }

    func testCurrentStateMatchMustBelongToReturnedHandoff() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(
            baseline: baseline,
            predicate: try currentStatePredicate()
        )
        let preliminary = await commit(label: "Preliminary")
        decision = reduce(decision, .observationAdmitted(await admission(preliminary, after: baseline)))
        let preliminaryEvaluation = try XCTUnwrap(
            decision.effects.compactMap(\.predicateEvaluation).first
        )
        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: preliminaryEvaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                path: .uikitIdle,
                observationBoundary: .after(preliminary.moment)
            ))
        )

        let handoff = await commit(label: "Handoff")
        decision = reduce(decision, .observationAdmitted(await admission(handoff, after: baseline)))
        XCTAssertNil(decision.state.result)
        let handoffEvaluation = try XCTUnwrap(
            decision.effects.compactMap(\.predicateEvaluation).first
        )
        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: handoffEvaluation.target,
                result: PredicateEvaluationResult(met: false, actual: "missing Save")
            ))
        )
        decision = reduce(decision, .deadlineReached)

        guard case .timedOut(let result) = decision.state else {
            return XCTFail("Expected the current-state mismatch at handoff to time out")
        }
        XCTAssertTrue(result.evidence.readiness.isEstablished)
        XCTAssertEqual(result.evidence.handoff.event?.moment, handoff.moment)
        XCTAssertFalse(result.evidence.predicate.isSatisfied)
    }

    func testTerminalStateEmitsNoFurtherEffects() async {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(baseline: baseline, predicate: nil)
        let ready = await commit(label: "Ready")
        decision = reduce(decision, .observationAdmitted(await admission(ready, after: baseline)))
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                path: .semanticStability,
                observationBoundary: .including(ready.moment)
            ))
        )
        guard case .completed = decision.state else {
            return XCTFail("Expected terminal settlement")
        }

        decision = reduce(decision, .deadlineReached)

        guard case .completed = decision.state else {
            return XCTFail("Terminal state must not change")
        }
        XCTAssertTrue(decision.effects.isEmpty)
    }

    func testTransitionResponsesLatchFirstMatchInObservationOrder() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(
            baseline: baseline,
            predicate: transitionPredicate()
        )
        let first = await commit(label: "First")
        decision = reduce(decision, .observationAdmitted(await admission(first, after: baseline)))
        let firstEvaluation = try XCTUnwrap(decision.effects.compactMap(\.predicateEvaluation).first)

        let second = await commit(label: "Second")
        decision = reduce(decision, .observationAdmitted(await admission(second, after: baseline)))
        let secondEvaluation = try XCTUnwrap(decision.effects.compactMap(\.predicateEvaluation).first)

        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: secondEvaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )
        XCTAssertNil(try activeSession(in: decision).requirement.evidence.satisfiedTarget)

        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: firstEvaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )

        let evidence = try activeSession(in: decision).requirement.evidence
        XCTAssertEqual(evidence.satisfiedTarget, firstEvaluation.target)
        XCTAssertEqual(
            evidence.rejectedResponses.map(\.reason),
            [.satisfactionAlreadyLatched]
        )
    }

    func testAnnouncementResponsesLatchFirstMatchInEventOrder() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(
            baseline: baseline,
            predicate: try announcementPredicate()
        )
        let first = announcement(sequence: 1, text: "Saved")
        decision = reduce(decision, .announcementObserved(first))
        let firstEvaluation = try XCTUnwrap(decision.effects.compactMap(\.predicateEvaluation).first)
        let second = announcement(sequence: 2, text: "Saving")
        decision = reduce(decision, .announcementObserved(second))
        let secondEvaluation = try XCTUnwrap(decision.effects.compactMap(\.predicateEvaluation).first)

        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: secondEvaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )
        XCTAssertNil(try activeSession(in: decision).requirement.evidence.satisfiedTarget)

        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: firstEvaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )

        let evidence = try activeSession(in: decision).requirement.evidence
        XCTAssertEqual(evidence.satisfiedTarget, firstEvaluation.target)
        XCTAssertEqual(
            evidence.rejectedResponses.map(\.reason),
            [.satisfactionAlreadyLatched]
        )
    }

    func testOrderedEvaluationAdvancesFromEarlierMissToLaterMatch() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(
            baseline: baseline,
            predicate: transitionPredicate()
        )
        let first = await commit(label: "First")
        decision = reduce(decision, .observationAdmitted(await admission(first, after: baseline)))
        let firstEvaluation = try XCTUnwrap(decision.effects.compactMap(\.predicateEvaluation).first)

        let second = await commit(label: "Second")
        decision = reduce(decision, .observationAdmitted(await admission(second, after: baseline)))
        let secondEvaluation = try XCTUnwrap(decision.effects.compactMap(\.predicateEvaluation).first)

        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: secondEvaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )
        XCTAssertNil(try activeSession(in: decision).requirement.evidence.satisfiedTarget)

        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: firstEvaluation.target,
                result: PredicateEvaluationResult(met: false)
            ))
        )

        let evidence = try activeSession(in: decision).requirement.evidence
        XCTAssertEqual(evidence.satisfiedTarget, secondEvaluation.target)
        XCTAssertEqual(
            evidence.responses.map(\.target),
            [firstEvaluation.target, secondEvaluation.target]
        )
        XCTAssertTrue(evidence.rejectedResponses.isEmpty)
    }

    func testStaleGenerationHandoffAdmissionCannotCompleteSettlement() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(baseline: baseline, predicate: nil)
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                path: .uikitIdle,
                observationBoundary: .after(baseline.moment)
            ))
        )
        decision = reduce(decision, .readinessInvalidated(.initial.advanced()))
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial.advanced(),
                path: .uikitIdle,
                observationBoundary: .after(baseline.moment)
            ))
        )

        let stale = await commit(label: "Stale")
        decision = reduce(
            decision,
            .observationAdmitted(await admission(
                stale,
                after: baseline,
                source: .handoffCapture(.initial)
            ))
        )
        XCTAssertNil(decision.state.result)
        XCTAssertNil(try activeSession(in: decision).handoff.event)

        let current = await commit(label: "Current")
        decision = reduce(
            decision,
            .observationAdmitted(await admission(
                current,
                after: baseline,
                source: .handoffCapture(.initial.advanced())
            ))
        )

        guard case .completed(let result) = decision.state else {
            return XCTFail("Expected only the active readiness generation to admit a handoff")
        }
        XCTAssertEqual(result.evidence.handoff.event?.moment, current.moment)
        XCTAssertEqual(result.evidence.handoff.generation, .initial.advanced())
    }

    func testDispatchFailureCannotEvaluatePredicateAndPreservesReadyHandoff() async throws {
        let baseline = await commit(label: "Baseline")
        let command = Settlement.Command(
            trigger: .action(.dismiss),
            predicate: transitionPredicate(),
            deadline: deadline
        )
        var decision = armedDecision(command: command, baseline: baseline)
        decision = reduce(
            decision,
            .dispatchCompleted(.failure(.dismiss, message: "Dispatch failed"))
        )
        let handoff = await commit(label: "Handoff")
        decision = reduce(decision, .observationAdmitted(await admission(handoff, after: baseline)))
        XCTAssertTrue(decision.effects.compactMap(\.predicateEvaluation).isEmpty)
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                path: .semanticStability,
                observationBoundary: .including(handoff.moment)
            ))
        )

        guard case .failed(let result) = decision.state else {
            return XCTFail("Expected failed dispatch to finish with diagnostic handoff")
        }
        XCTAssertEqual(result.outcome, .dispatchFailed)
        XCTAssertTrue(result.evidence.predicate.isNotEvaluated)
        XCTAssertEqual(result.evidence.handoff.event?.moment, handoff.moment)
    }

    func testCancellationPreservesIndependentEvidenceAndStopsEffects() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(
            baseline: baseline,
            predicate: transitionPredicate()
        )
        let transient = await commit(label: "Transient")
        decision = reduce(decision, .observationAdmitted(await admission(transient, after: baseline)))
        let evaluation = try XCTUnwrap(decision.effects.compactMap(\.predicateEvaluation).first)
        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: evaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )
        decision = reduce(decision, .cancelled)

        guard case .cancelled(let result) = decision.state else {
            return XCTFail("Expected cancellation to terminate settlement")
        }
        XCTAssertTrue(result.evidence.predicate.isSatisfied)
        XCTAssertFalse(result.evidence.readiness.isEstablished)
        XCTAssertEqual(decision.effects.filter(\.isFinish).count, 1)

        decision = reduce(decision, .deadlineReached)
        XCTAssertTrue(decision.effects.isEmpty)
    }

    func testHistoryAndAnnouncementGapsRemainTypedFailures() async throws {
        let baseline = await commit(label: "Baseline")
        let current = await commit(label: "Current")
        let historyGap = Observation.Gap(
            reason: .historyEvicted,
            baseline: baseline.moment,
            current: current.moment
        )
        var transitionDecision = armedObservationDecision(
            baseline: baseline,
            predicate: transitionPredicate()
        )
        transitionDecision = reduce(
            transitionDecision,
            .observationHistoryUnavailable(.expired(historyGap))
        )
        XCTAssertEqual(
            try activeSession(in: transitionDecision).requirement.evidence.unavailability,
            .historyExpired(historyGap)
        )

        var announcementDecision = armedObservationDecision(
            baseline: baseline,
            predicate: try announcementPredicate()
        )
        let announcementGap = AccessibilityNotificationGap(droppedThroughSequence: 7)
        announcementDecision = reduce(
            announcementDecision,
            .announcementHistoryUnavailable(announcementGap)
        )
        XCTAssertEqual(
            try activeSession(in: announcementDecision).requirement.evidence.unavailability,
            .announcementHistoryUnavailable(announcementGap)
        )
    }

    func testCompleteHistoryGapCannotSatisfyAtHandoff() async throws {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(
            baseline: baseline,
            predicate: completeHistoryPredicate()
        )
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                path: .uikitIdle,
                observationBoundary: .after(baseline.moment)
            ))
        )
        let handoff = await commit(label: "Handoff")
        let gap = Observation.Gap(
            reason: .historyEvicted,
            baseline: baseline.moment,
            current: handoff.moment
        )
        decision = reduce(
            decision,
            .observationAdmitted(.init(
                event: handoff,
                history: .expired(gap),
                source: .handoffCapture(.initial)
            ))
        )
        XCTAssertTrue(decision.effects.compactMap(\.predicateEvaluation).isEmpty)
        decision = reduce(decision, .deadlineReached)

        guard case .timedOut(let result) = decision.state else {
            return XCTFail("Expected incomplete history to prevent settlement")
        }
        XCTAssertEqual(result.evidence.predicate.unavailability, .historyExpired(gap))
        XCTAssertEqual(result.evidence.handoff.event?.moment, handoff.moment)
    }

    func testHandoffCaptureFailureRemainsDistinctFromReadiness() async {
        let baseline = await commit(label: "Baseline")
        var decision = armedObservationDecision(baseline: baseline, predicate: nil)
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                path: .uikitIdle,
                observationBoundary: .after(baseline.moment)
            ))
        )
        decision = reduce(
            decision,
            .handoffCaptureFailed(.initial, .admissionRejected)
        )
        decision = reduce(decision, .deadlineReached)

        guard case .timedOut(let result) = decision.state else {
            return XCTFail("Expected failed handoff capture to time out")
        }
        XCTAssertTrue(result.evidence.readiness.isEstablished)
        XCTAssertEqual(
            result.evidence.handoff,
            .captureFailed(.initial, .admissionRejected)
        )
    }

    func testDeadlinePreservesReadinessPredicateAndHandoffAxesIndependently() async throws {
        let baseline = await commit(label: "Baseline")

        var predicateOnly = armedObservationDecision(
            baseline: baseline,
            predicate: transitionPredicate()
        )
        let transient = await commit(label: "Transient")
        predicateOnly = reduce(
            predicateOnly,
            .observationAdmitted(await admission(transient, after: baseline))
        )
        let evaluation = try XCTUnwrap(predicateOnly.effects.compactMap(\.predicateEvaluation).first)
        predicateOnly = reduce(
            predicateOnly,
            .predicateEvaluated(.init(
                target: evaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )
        let predicateOnlyResult = try timedOutResult(from: reduce(predicateOnly, .deadlineReached))
        XCTAssertTrue(predicateOnlyResult.evidence.predicate.isSatisfied)
        XCTAssertFalse(predicateOnlyResult.evidence.readiness.isEstablished)
        XCTAssertNil(predicateOnlyResult.evidence.handoff.event)

        var readinessAndHandoff = armedObservationDecision(
            baseline: baseline,
            predicate: transitionPredicate()
        )
        let ready = await commit(label: "Ready")
        readinessAndHandoff = reduce(
            readinessAndHandoff,
            .observationAdmitted(await admission(ready, after: baseline))
        )
        let unmetEvaluation = try XCTUnwrap(
            readinessAndHandoff.effects.compactMap(\.predicateEvaluation).first
        )
        readinessAndHandoff = reduce(
            readinessAndHandoff,
            .predicateEvaluated(.init(
                target: unmetEvaluation.target,
                result: PredicateEvaluationResult(met: false)
            ))
        )
        readinessAndHandoff = reduce(
            readinessAndHandoff,
            .readinessEstablished(.init(
                generation: .initial,
                path: .semanticStability,
                observationBoundary: .including(ready.moment)
            ))
        )
        let readinessAndHandoffResult = try timedOutResult(
            from: reduce(readinessAndHandoff, .deadlineReached)
        )
        XCTAssertTrue(readinessAndHandoffResult.evidence.readiness.isEstablished)
        XCTAssertNotNil(readinessAndHandoffResult.evidence.handoff.event)
        XCTAssertFalse(readinessAndHandoffResult.evidence.predicate.isSatisfied)

        var readyPredicateWithoutHandoff = predicateOnly
        readyPredicateWithoutHandoff = reduce(
            readyPredicateWithoutHandoff,
            .readinessEstablished(.init(
                generation: .initial,
                path: .uikitIdle,
                observationBoundary: .after(transient.moment)
            ))
        )
        let readyPredicateResult = try timedOutResult(
            from: reduce(readyPredicateWithoutHandoff, .deadlineReached)
        )
        XCTAssertTrue(readyPredicateResult.evidence.readiness.isEstablished)
        XCTAssertTrue(readyPredicateResult.evidence.predicate.isSatisfied)
        XCTAssertNil(readyPredicateResult.evidence.handoff.event)

        let neitherResult = try timedOutResult(from: reduce(
            armedObservationDecision(baseline: baseline, predicate: transitionPredicate()),
            .deadlineReached
        ))
        XCTAssertFalse(neitherResult.evidence.readiness.isEstablished)
        XCTAssertFalse(neitherResult.evidence.predicate.isSatisfied)
        XCTAssertNil(neitherResult.evidence.handoff.event)
    }

    private var deadline: Settlement.Deadline {
        Settlement.Deadline(instant: ContinuousClock.now.advanced(by: .seconds(1)))
    }

    private func transitionPredicate() -> Settlement.Predicate {
        Settlement.Predicate(
            authored: .changed(.elements()),
            resolved: ResolvedAccessibilityPredicate(core: .changed(.elements([])))
        )
    }

    private func currentStatePredicate() throws -> Settlement.Predicate {
        let authored = AccessibilityPredicate.exists(
            .predicate(ElementPredicateTemplate(label: "Save"))
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

    private func completeHistoryPredicate() -> Settlement.Predicate {
        Settlement.Predicate(
            authored: .noChange,
            resolved: ResolvedAccessibilityPredicate(core: .noChange)
        )
    }

    private func armedObservationDecision(
        baseline: Observation.SnapshotEvent,
        predicate: Settlement.Predicate?
    ) -> Settlement.Decision {
        var decision = Settlement.Reducer.begin(Settlement.Command(
            trigger: .observation,
            predicate: predicate,
            deadline: deadline
        ))
        decision = reduce(
            decision,
            .baselineAdmitted(.init(moment: baseline.moment))
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
            .baselineAdmitted(.init(moment: baseline.moment))
        )
        return reduce(decision, .channelsArmed)
    }

    private func admission(
        _ event: Observation.SnapshotEvent,
        after baseline: Observation.SnapshotEvent,
        source: Settlement.ObservationAdmissionSource = .observation
    ) async -> Settlement.ObservationAdmission {
        Settlement.ObservationAdmission(
            event: event,
            history: .events(Array(await vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: baseline.moment).events
            })),
            source: source
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
        switch decision.state {
        case .armed(let session),
             .dispatching(let session),
             .observing(let session),
             .needHandoff(let session):
            return session
        case .awaitingBaseline, .completed, .failed, .timedOut, .cancelled:
            throw ActiveSessionError.unavailable
        }
    }

    private func timedOutResult(from decision: Settlement.Decision) throws -> Settlement.Result {
        guard case .timedOut(let result) = decision.state else {
            throw TimedOutResultError.unavailable
        }
        return result
    }

    private func commit(label: String) async -> Observation.SnapshotEvent {
        await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(
                label: label,
                heistId: HeistId(rawValue: label.lowercased())
            )
        )
    }

    private func truthObservation(
        label: String,
        value: String? = nil,
        heistId: HeistId
    ) -> InterfaceObservation {
        InterfaceObservation.makeForTests(elements: [(
            AccessibilityElement.make(label: label, value: value, traits: .staticText),
            heistId
        )])
    }

    private func canonicalEvaluation(
        _ authored: AccessibilityPredicate,
        event: Observation.SnapshotEvent,
        history: Observation.EventsSince
    ) async throws -> PredicateEvaluationResult {
        let predicate = Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
        let evidence: Settlement.Predicate.EvaluationEvidence = switch predicate.semantics {
        case .currentState:
            .currentState(event)
        case .positiveTransition:
            .positiveTransition(event)
        case .completeHistory:
            .completeHistory(.init(history: history, handoff: event))
        case .announcement:
            preconditionFailure("Truth matrix does not synthesize announcement evidence")
        }
        let command = Settlement.Command(
            trigger: .observation,
            predicate: predicate,
            deadline: .init(instant: ContinuousClock.now.advanced(by: .seconds(1)))
        )
        let boundary = LiveSettlementExecutionBoundary(
            command: command,
            vault: vault,
            tripwire: TheTripwire(),
            dispatch: { _ in .success(payload: .dismiss) },
            observationEffects: { _ in }
        )
        return await boundary.evaluate(.init(
            predicate: predicate,
            target: .observation(event.moment),
            evidence: evidence
        ))
    }

    private func reduce(
        _ decision: Settlement.Decision,
        _ fact: Settlement.Event.Fact
    ) -> Settlement.Decision {
        Settlement.Reducer.reduce(
            decision.state,
            event: Settlement.Event(
                fact: fact,
                elapsed: RuntimeElapsed.admit(milliseconds: 1)
            )
        )
    }
}

private enum ActiveSessionError: Error {
    case unavailable
}

private enum TimedOutResultError: Error {
    case unavailable
}

private struct ProductRow: CustomStringConvertible {
    let trigger: Settlement.Trigger
    let hasPredicate: Bool
    let dispatchCount: Int

    var description: String {
        "trigger=\(trigger), predicate=\(hasPredicate)"
    }
}

private struct PredicateTruthRow {
    let name: String
    let preBaseline: InterfaceObservation?
    let baseline: InterfaceObservation
    let observed: InterfaceObservation
    let predicate: AccessibilityPredicate
    let expected: Bool
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

    var predicateEvaluation: Settlement.Predicate.EvaluationRequest? {
        guard case .evaluatePredicate(let request) = self else { return nil }
        return request
    }

    var isFinish: Bool {
        guard case .finish = self else { return false }
        return true
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
