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
    func testTimedCommandsRequireReadinessAndHandoff() async throws {
        let predicate = transitionPredicate()
        let rows = [
            ProductRow(
                command: .action(.init(
                    command: .dismiss,
                    predicate: nil,
                    allowances: .init(readiness: .seconds(5), expectation: nil),
                    baseline: .capture
                )),
                dispatchCount: 1
            ),
            ProductRow(
                command: .action(.init(
                    command: .dismiss,
                    predicate: predicate,
                    allowances: .init(readiness: .seconds(5), expectation: .seconds(1)),
                    baseline: .capture
                )),
                dispatchCount: 1
            ),
            ProductRow(
                command: .observation(
                    predicate: predicate,
                    deadline: deadline,
                    baseline: .capture
                ),
                dispatchCount: 0
            ),
        ]

        for row in rows {
            let baseline = await commit(label: "Baseline")
            let command = row.command
            var decision = Settlement.Reducer.begin(command)
            var dispatchCount = 0

            decision = reduce(
                decision,
                .baselineAdmitted(baseline)
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
                    path: .semanticStability,
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
            decision = completeQuiescence(decision)
            guard case .terminal(let result) = decision.state else {
                XCTFail("Expected readiness and an admitted handoff to complete \(row)")
                continue
            }
            switch result {
            case .observation(.settled(let settled)):
                XCTAssertEqual(settled.boundary.moment, baseline.moment)
                XCTAssertEqual(settled.handoff.event.moment, handoff.moment)
            case .action(.settled(let settled)):
                XCTAssertEqual(settled.boundary.moment, baseline.moment)
                XCTAssertEqual(settled.handoff.event.moment, handoff.moment)
            case .currentState, .observation(.failed), .action(.failed):
                XCTFail("Expected settled command result for \(row)")
            }
        }
    }

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
            .changed(.elements([.appeared(target)])),
            .announcement("Saved"),
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

    func testArmedAndActiveTerminalCausesEnterQuiescenceWithoutResult() async {
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
            assertQuiescing(decision, name)
        }
    }

    func testViewportExitFinalizesOrReplacesTheIntendedOutcome() async {
        let baseline = await commit(label: "Baseline")
        let handoff = await commit(label: "Handoff")
        var settled = armedPredicateFreeActionDecision(baseline: baseline)
        settled = reduce(
            settled,
            .observationAdmitted(await admission(handoff, after: baseline))
        )
        settled = reduce(
            settled,
            .readinessEstablished(.init(
                generation: .initial,
                path: .semanticStability,
                observationBoundary: .including(handoff.moment)
            ))
        )

        for viewportExit in [
            Navigation.ViewportExit.Outcome.restored,
            .retained,
            .superseded,
        ] {
            let decision = reduce(settled, .quiesced(viewportExit))
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
                .quiesced(.failed(.originUnavailable))
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

    func testPreReadinessEvidenceSettlesFromOriginalBaseline() async throws {
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
                path: .semanticStability,
                observationBoundary: .after(transient.moment)
            ))
        )
        XCTAssertEqual(decision.effects.filter(\.isHandoffCapture).count, 1)
        decision = reduce(decision, .readinessInvalidated(.initial.advanced()))
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial.advanced(),
                path: .semanticStability,
                observationBoundary: .after(transient.moment)
            ))
        )
        XCTAssertEqual(decision.effects.filter(\.isHandoffCapture).count, 1)

        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial.advanced(),
                path: .semanticStability,
                observationBoundary: .after(transient.moment)
            ))
        )
        XCTAssertTrue(decision.effects.isEmpty)

        let final = await commit(label: "Final")
        decision = reduce(decision, .observationAdmitted(await admission(final, after: baseline)))
        decision = completeQuiescence(decision)
        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected the latched transition to survive readiness invalidation")
        }
        guard case .observation(.settled(let settled)) = result else {
            return XCTFail("Expected settled observation")
        }
        XCTAssertEqual(settled.boundary.moment, baseline.moment)
        XCTAssertEqual(settled.evaluation.target, evaluation.target)
        XCTAssertEqual(settled.handoff.event.moment, final.moment)
        XCTAssertEqual(settled.history?.events, [
            .snapshot(transient),
            .snapshot(final),
        ])
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
                path: .semanticStability,
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
        decision = reduce(
            decision,
            .deadlineReached(.init(
                phase: .observation,
                instant: deadline.instant
            ))
        )

        decision = completeQuiescence(decision)
        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected the current-state mismatch at handoff to time out")
        }
        guard case .observation(.failed(let failed)) = result else {
            return XCTFail("Expected failed observation")
        }
        XCTAssertEqual(failed.reason, .timedOut(.observation))
        XCTAssertTrue(failed.attempt.readiness.isEstablished)
        XCTAssertEqual(failed.attempt.handoff.event?.moment, handoff.moment)
        XCTAssertFalse(failed.attempt.evaluation.isSatisfied)
    }

    func testActionCurrentStateMatchPromotesReturnedHandoff() async throws {
        let baseline = await commit(label: "Baseline")
        let ready = await commit(label: "Ready")
        let dispatchAt = ContinuousClock.now
        var decision = try await actionAwaitingEvidence(
            baseline: baseline,
            ready: ready,
            dispatchAt: dispatchAt,
            readyAt: dispatchAt.advanced(by: .milliseconds(100)),
            predicate: try currentStatePredicate()
        )

        let matching = await commit(label: "Save")
        decision = reduce(
            decision,
            .observationAdmitted(await admission(matching, after: baseline))
        )
        let matchingEvaluation = try XCTUnwrap(
            decision.effects.compactMap(\.predicateEvaluation).first
        )
        decision = reduce(
            decision,
            .predicateEvaluated(.init(
                target: matchingEvaluation.target,
                result: PredicateEvaluationResult(met: true)
            ))
        )

        decision = completeQuiescence(decision)
        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected the matching current-state observation to settle the action")
        }
        guard case .action(.settled(let settled)) = result else {
            return XCTFail("Expected settled action")
        }
        XCTAssertEqual(settled.handoff.event.moment, matching.moment)
        XCTAssertEqual(
            settled.evaluation?.target,
            .observation(matching.moment)
        )
    }

    func testTerminalStateEmitsNoFurtherEffects() async {
        let baseline = await commit(label: "Baseline")
        var decision = armedPredicateFreeActionDecision(baseline: baseline)
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
        decision = completeQuiescence(decision)
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
        var decision = armedPredicateFreeActionDecision(baseline: baseline)
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                path: .semanticStability,
                observationBoundary: .after(baseline.moment)
            ))
        )
        decision = reduce(decision, .readinessInvalidated(.initial.advanced()))
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial.advanced(),
                path: .semanticStability,
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

        decision = completeQuiescence(decision)
        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected only the active readiness generation to admit a handoff")
        }
        guard case .action(.settled(let settled)) = result else {
            return XCTFail("Expected settled action")
        }
        XCTAssertEqual(settled.handoff.event.moment, current.moment)
        XCTAssertEqual(settled.handoff.generation, .initial.advanced())
    }

    func testDispatchFailureCannotEvaluatePredicateAndPreservesReadyHandoff() async throws {
        let baseline = await commit(label: "Baseline")
        let command = Settlement.Command.action(.init(
            command: .dismiss,
            predicate: transitionPredicate(),
            allowances: .init(readiness: .seconds(5), expectation: .seconds(1)),
            baseline: .capture
        ))
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

        decision = completeQuiescence(decision)
        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected failed dispatch to finish with diagnostic handoff")
        }
        guard case .action(.failed(let failed)) = result else {
            return XCTFail("Expected failed action")
        }
        XCTAssertEqual(failed.reason, .dispatchFailed)
        XCTAssertTrue(failed.attempt.evaluation.isNotEvaluated)
        XCTAssertEqual(failed.attempt.handoff.event?.moment, handoff.moment)
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

        decision = completeQuiescence(decision)
        guard case .terminal(let result) = decision.state else {
            return XCTFail("Expected cancellation to terminate settlement")
        }
        guard case .observation(.failed(let failed)) = result else {
            return XCTFail("Expected cancelled observation")
        }
        XCTAssertEqual(failed.reason, .cancelled)
        XCTAssertTrue(failed.attempt.evaluation.isSatisfied)
        XCTAssertFalse(failed.attempt.readiness.isEstablished)

        decision = reduce(
            decision,
            .deadlineReached(.init(
                phase: .observation,
                instant: deadline.instant
            ))
        )
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

    func testHandoffCaptureFailureRemainsDistinctFromReadiness() async {
        let baseline = await commit(label: "Baseline")
        var decision = armedPredicateFreeActionDecision(baseline: baseline)
        decision = reduce(
            decision,
            .readinessEstablished(.init(
                generation: .initial,
                path: .semanticStability,
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

        decision = completeQuiescence(decision)
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
                path: .semanticStability,
                observationBoundary: .including(nextReady.moment)
            )),
            elapsed: 3_500
        )
        decision = reduce(
            decision,
            .observationAdmitted(await admission(
                nextReady,
                after: baseline,
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
            authored: .changed(.elements()),
            resolved: .changed(.elements([]))
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
                path: .semanticStability,
                observationBoundary: .including(ready.moment)
            )),
            elapsed: readyElapsed
        )
        decision = reduce(
            decision,
            .observationAdmitted(await admission(
                ready,
                after: baseline,
                source: .handoffCapture(.initial),
                instant: readyAt
            )),
            elapsed: readyElapsed,
            instant: readyAt
        )
        guard predicate.semantics != .announcement else { return decision }
        let evaluation = try XCTUnwrap(
            decision.effects.compactMap(\.predicateEvaluation).first
        )
        return reduce(
            decision,
            .predicateEvaluated(.init(
                target: evaluation.target,
                result: PredicateEvaluationResult(met: false)
            )),
            elapsed: readyElapsed
        )
    }

    private func admission(
        _ event: Observation.SnapshotEvent,
        after baseline: Observation.SnapshotEvent,
        source: Settlement.ObservationAdmissionSource = .observation,
        instant: ContinuousClock.Instant = RuntimeElapsed.now
    ) async -> Settlement.ObservationAdmission {
        Settlement.ObservationAdmission(
            event: event,
            history: .events(Array(await vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: baseline.moment).events
            })),
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
        let command = Settlement.Command.observation(
            predicate: predicate,
            deadline: .init(
                phase: .observation,
                instant: ContinuousClock.now.advanced(by: .seconds(1))
            ),
            baseline: .capture
        )
        let boundary = LiveSettlementExecutionBoundary(
            command: command,
            vault: vault,
            tripwire: TheTripwire(),
            dispatch: { _ in .success(payload: .dismiss) },
            observationEffects: { _ in .restored }
        )
        return boundary.evaluate(.init(
            predicate: predicate,
            target: .observation(event.moment),
            evidence: evidence
        ))
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

    private func completeQuiescence(
        _ decision: Settlement.Decision,
        viewportExit: Navigation.ViewportExit.Outcome = .restored
    ) -> Settlement.Decision {
        assertQuiescing(decision)
        return reduce(decision, .quiesced(viewportExit))
    }

    private func assertQuiescing(
        _ decision: Settlement.Decision,
        _ message: String = ""
    ) {
        XCTAssertNil(decision.state.result, message)
        guard case .quiescing = decision.state else {
            return XCTFail("Expected Settlement to quiesce before terminal state \(message)")
        }
        XCTAssertEqual(decision.effects.count, 1, message)
        guard case .quiesce = decision.effects.first else {
            return XCTFail("Expected exactly one quiescence effect \(message)")
        }
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
                 .evaluatePredicate,
                 .quiesce:
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
