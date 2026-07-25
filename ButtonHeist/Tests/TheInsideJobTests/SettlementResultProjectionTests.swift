#if canImport(UIKit)
#if DEBUG
import Foundation
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import ThePlans
@testable import TheScore

@MainActor
final class SettlementResultProjectionTests: SemanticObservationStreamTestCase {
    func testWaitProjectionPreservesMatchedAndFailedEvidenceSummaries() async throws {
        let baseline = await commit(label: "Loading")
        let observed = await commit(label: "Ready")
        let predicate = try predicate(.exists(.label("Ready")))
        let matched = Settlement.ResultProjector.projectWait(
            await settledWait(
                predicate: predicate,
                baseline: baseline,
                observed: observed,
                elapsed: 1_500
            )
        )
        let failed = Settlement.ResultProjector.projectWait(
            await failedWait(
                reason: .timedOut(.observation),
                predicate: predicate,
                baseline: baseline,
                observed: observed,
                predicateMet: false
            )
        )

        XCTAssertEqual(matched.outcome, .matched)
        XCTAssertEqual(matched.actionResult.outcome, .success)
        XCTAssertEqual(matched.actionResult.message, "matched after 1.5s")
        XCTAssertEqual(matched.expectation.actual, "matched")
        XCTAssertEqual(matched.baselineSummary, baseline.moment.capture.summary)
        XCTAssertEqual(matched.finalSummary, "matched")

        XCTAssertEqual(failed.outcome, .failed)
        XCTAssertEqual(failed.actionResult.outcome, .failure(.timeout))
        XCTAssertEqual(failed.expectation.actual, "missing")
        XCTAssertEqual(failed.baselineSummary, baseline.moment.capture.summary)
        XCTAssertEqual(failed.finalSummary, "missing")
    }

    func testSuccessfulActionProjectsCompleteTraceSettlementPathAndTiming() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commit(label: "Observed")
        let handler = try ScreenActionHandlerName(validating: "root escape")
        let dispatch = TheSafecracker.ActionDispatchResult.success(
            payload: .dismiss,
            message: "dismissed",
            screenActionHandler: handler
        )
        let projection = Settlement.ResultProjector.projectAction(
            await settledAction(
                command: .dismiss,
                dispatch: dispatch,
                baseline: baseline,
                observed: observed,
                timing: timing(
                    elapsed: 25,
                    beforeObservation: 3,
                    finalSemanticEvidence: 5
                )
            )
        )
        let result = try XCTUnwrap(projection.result)
        let trace = try XCTUnwrap(result.traceEvidence)

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.message, "dismissed")
        XCTAssertEqual(result.screenActionHandler, handler)
        XCTAssertEqual(trace.completeness, .complete)
        XCTAssertEqual(trace.trace, observed.trace)
        XCTAssertEqual(trace.trace.captures.first, baseline.moment.capture)
        XCTAssertEqual(trace.trace.captures.last, observed.moment.capture)
        XCTAssertEqual(result.evidence.settlement, .settled(duration: 25))
        XCTAssertEqual(result.timing?.beforeObservationMs, 3)
        XCTAssertEqual(result.timing?.finalSemanticEvidenceMs, 5)
    }

    func testTypeTextPayloadRefreshesFromExactHandoffElement() async throws {
        let selectedId: HeistId = "selected_message"
        let baseline = await commit(label: "Baseline")
        let observed = await commit(.makeForTests(elements: [
            (
                AccessibilityElement.make(
                    label: "Message",
                    value: "Selected",
                    traits: .textEntry
                ),
                selectedId
            ),
            (
                AccessibilityElement.make(
                    label: "Message",
                    value: "Replacement",
                    traits: .textEntry
                ),
                HeistId(rawValue: "replacement_message")
            ),
        ]))
        let command = try HeistActionCommand.typeText(
            text: "new value",
            target: .label("Message")
        ).resolve(in: .empty)
        let dispatch = TheSafecracker.ActionDispatchResult.success(
            payload: .typeText(nil),
            resolvedElementId: selectedId
        )

        let projection = Settlement.ResultProjector.projectAction(
            await settledAction(
                command: command,
                dispatch: dispatch,
                baseline: baseline,
                observed: observed
            )
        )

        XCTAssertEqual(projection.result?.payload, .typeText("Selected"))
    }

    func testDispatchFailurePreservesDispatchEvidenceWithoutExpectation() async throws {
        let baseline = await commit(label: "Baseline")
        let dispatch = TheSafecracker.ActionDispatchResult.failure(
            .dismiss,
            message: "target disappeared",
            failureKind: .targetUnavailable
        )
        let result = Settlement.Result.action(.failed(.init(
            reason: .dispatchFailed,
            attempt: .init(
                command: actionCommand(.dismiss),
                boundary: .established(.init(moment: baseline.moment)),
                dispatch: .completed(dispatch),
                outstanding: [],
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                history: .events([]),
                timing: timing(elapsed: 4)
            )
        )))

        let projection = Settlement.ResultProjector.projectAction(result)

        XCTAssertNil(projection.expectation)
        XCTAssertEqual(projection.result?.outcome, .failure(.elementNotFound))
        XCTAssertEqual(projection.result?.message, "target disappeared")
    }

    func testBaselineUnavailableProjectsTypedTreeFailure() throws {
        let predicate = try predicate(.exists(.label("Ready")))
        let wait = Settlement.Result.observation(.failed(.init(
            reason: .baselineUnavailable,
            attempt: .init(
                predicate: predicate,
                boundary: .unavailable(.unavailable),
                outstanding: Expectation([predicate.resolved]).outstanding,
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                history: nil,
                timing: timing(elapsed: 0)
            )
        )))

        let waitProjection = Settlement.ResultProjector.projectWait(wait)

        XCTAssertEqual(waitProjection.actionResult.outcome, .failure(.accessibilityTreeUnavailable))
        XCTAssertEqual(waitProjection.actionResult.message, TheBrains.treeUnavailableMessage)
        XCTAssertNil(waitProjection.baselineSummary)
    }

    func testWaitTimeoutReportsCurrentCandidateDiagnostics() async throws {
        let baseline = await commit(label: "Baseline")
        let candidate = AccessibilityElement.make(
            label: "Ticket saved., Dismiss",
            identifier: "dismiss_banner",
            customActions: [.init(name: "Archive")],
            customRotors: [.init(name: "Errors")],
            respondsToUserInteraction: false
        )
        let observed = await commit(.makeForTests(elements: [
            (candidate, HeistId(rawValue: "dismiss_banner")),
        ]))
        let predicate = try predicate(.exists(.label("Ticket saved.")))
        let settlement = await failedWait(
            reason: .timedOut(.observation),
            predicate: predicate,
            baseline: baseline,
            observed: observed,
            predicateMet: false
        )

        let message = try XCTUnwrap(
            Settlement.ResultProjector.projectWait(settlement).actionResult.message
        )

        XCTAssertTrue(message.contains("waiting for element to appear"), message)
        XCTAssertTrue(message.contains(#"expected: label="Ticket saved.""#), message)
        XCTAssertTrue(message.contains("interface: 1 elements"), message)
        XCTAssertTrue(message.contains("last result: element not found"), message)
        XCTAssertTrue(message.contains("identifier=\"dismiss_banner\""), message)
        XCTAssertTrue(message.contains("actions=[activate, Archive]"), message)
        XCTAssertTrue(message.contains("rotors=[\"Errors\"]"), message)
        XCTAssertTrue(message.contains("did not match"), message)
    }

    func testCancellationProjectsIncompleteTraceAndSettlementTiming() async throws {
        let baseline = await commit(label: "Save")
        let result = Settlement.Result.action(.failed(.init(
            reason: .cancelled,
            attempt: .init(
                command: actionCommand(.dismiss),
                boundary: .established(.init(moment: baseline.moment)),
                dispatch: .completed(.success(payload: .dismiss)),
                outstanding: [],
                readiness: .pending(.initial),
                handoff: .pending(.initial),
                history: .events([]),
                timing: timing(elapsed: 125, beforeObservation: 7)
            )
        )))

        let action = try XCTUnwrap(
            Settlement.ResultProjector.projectAction(result).result
        )
        let trace = try XCTUnwrap(action.traceEvidence)

        XCTAssertEqual(action.outcome, .failure(.actionFailed))
        XCTAssertEqual(action.message, "cancelled after 125ms")
        XCTAssertEqual(action.evidence.settlement, .timedOut(duration: 125))
        XCTAssertEqual(action.timing?.beforeObservationMs, 7)
        XCTAssertEqual(trace.completeness, .incomplete)
        XCTAssertEqual(trace.trace.captures, [baseline.moment.capture])
    }
    func predicate(_ authored: AccessibilityPredicate) throws -> Settlement.Predicate {
        Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
    }

    func settledWait(
        predicate: Settlement.Predicate,
        baseline: Observation.SnapshotEvent,
        observed: Observation.SnapshotEvent,
        elapsed: ElapsedMilliseconds
    ) async -> Settlement.Result {
        return .observation(.settled(.init(
            predicate: predicate,
            boundary: .init(moment: baseline.moment),
            readiness: readiness(at: observed),
            handoff: await handoffAdmission(observed, baseline: baseline),
            history: await history(after: baseline),
            timing: timing(elapsed: elapsed)
        )))
    }

    func failedWait(
        reason: Settlement.Result.ObservationFailureReason,
        predicate: Settlement.Predicate,
        baseline: Observation.SnapshotEvent,
        observed: Observation.SnapshotEvent,
        predicateMet: Bool
    ) async -> Settlement.Result {
        .observation(.failed(.init(
            reason: reason,
            attempt: .init(
                predicate: predicate,
                boundary: .established(.init(moment: baseline.moment)),
                outstanding: predicateMet ? [] : Expectation([predicate.resolved]).outstanding,
                readiness: .established(readiness(at: observed)),
                handoff: .admitted(await handoffAdmission(observed, baseline: baseline)),
                history: await history(after: baseline),
                timing: timing(elapsed: 25)
            )
        )))
    }

    func settledAction(
        command: ResolvedHeistActionCommand,
        dispatch: TheSafecracker.ActionDispatchResult,
        baseline: Observation.SnapshotEvent,
        observed: Observation.SnapshotEvent,
        timing: Settlement.Result.Timing? = nil
    ) async -> Settlement.Result {
        .action(.settled(.init(
            command: actionCommand(command),
            boundary: .init(moment: baseline.moment),
            dispatch: dispatch,

            readiness: readiness(at: observed),
            handoff: await handoffAdmission(observed, baseline: baseline),
            history: await history(after: baseline),
            timing: timing ?? self.timing(elapsed: 25)
        )))
    }

    func actionCommand(
        _ command: ResolvedHeistActionCommand
    ) -> Settlement.Command.Action {
        Settlement.Command.Action(
            command: command,
            predicate: nil,
            allowances: .init(readiness: .seconds(5), expectation: nil),
            baseline: .capture
        )
    }

    func timing(
        elapsed: ElapsedMilliseconds,
        beforeObservation: ElapsedMilliseconds? = nil,
        finalSemanticEvidence: ElapsedMilliseconds? = nil
    ) -> Settlement.Result.Timing {
        Settlement.Result.Timing(
            execution: .init(
                beforeObservationMs: beforeObservation,
                finalSemanticEvidenceMs: finalSemanticEvidence
            ),
            elapsed: elapsed
        )
    }

    func readiness(
        at event: Observation.SnapshotEvent
    ) -> Settlement.Readiness.Establishment {
        Settlement.Readiness.Establishment(
            generation: .initial,
            path: .semanticStability,
            observationBoundary: .including(event.moment)
        )
    }

    func handoffAdmission(
        _ event: Observation.SnapshotEvent,
        baseline: Observation.SnapshotEvent
    ) async -> Settlement.Handoff.Admission {
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
        return handoff
    }

    func history(
        after baseline: Observation.SnapshotEvent
    ) async -> Observation.EventsSince {
        await vault.semanticObservationStream.storeOwner.readLog {
            $0.events(since: baseline.moment)
        }
    }

    func commit(label: String) async -> Observation.SnapshotEvent {
        await commit(observation(
            label: label,
            heistId: HeistId(rawValue: label.lowercased())
        ))
    }

    func commit(
        _ observation: InterfaceObservation
    ) async -> Observation.SnapshotEvent {
        await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
