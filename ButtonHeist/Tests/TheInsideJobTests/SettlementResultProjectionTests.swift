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
        let observed = await commitSettling(label: "Ready")
        let present = try predicate(.exists(.label("Ready")))
        let absent = try predicate(.exists(.label("Missing")))
        let matched = Settlement.ResultProjector.projectWait(
            wait(
                predicate: present,
                baseline: baseline,
                observed: observed,
                elapsed: 1_500
            )
        )
        let failed = Settlement.ResultProjector.projectWait(
            wait(
                predicate: absent,
                baseline: baseline,
                observed: observed
            )
        )

        // A matched wait has nothing outstanding: the drain is the evidence, so
        // there is no summary of what was still missing to report.
        XCTAssertEqual(matched.outcome, .matched)
        XCTAssertEqual(matched.actionResult.outcome, .success)
        XCTAssertEqual(matched.actionResult.message, "matched after 1.5s")
        XCTAssertNil(matched.expectation.actual)
        XCTAssertEqual(matched.baselineSummary, baseline.moment.capture.summary)
        XCTAssertNil(matched.finalSummary)

        // A failed wait reports what it was still waiting on, and the same text
        // reaches both the expectation and the summary.
        XCTAssertEqual(failed.outcome, .failed)
        XCTAssertEqual(failed.actionResult.outcome, .failure(.timeout))
        XCTAssertEqual(failed.baselineSummary, baseline.moment.capture.summary)
        XCTAssertEqual(failed.finalSummary, failed.expectation.actual)
        let outstanding = try XCTUnwrap(failed.expectation.actual)
        XCTAssertTrue(outstanding.contains("Missing"), outstanding)
    }

    func testSuccessfulActionProjectsCompleteTraceSettlementPathAndTiming() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commitSettling(label: "Observed")
        let handler = try ScreenActionHandlerName(validating: "root escape")
        let dispatch = TheSafecracker.ActionDispatchResult.success(
            payload: .dismiss,
            message: "dismissed",
            screenActionHandler: handler
        )
        let projection = Settlement.ResultProjector.projectAction(
            action(
                .dismiss,
                dispatch: dispatch,
                baseline: baseline,
                observed: observed
            )
        )
        let result = try XCTUnwrap(projection.result)
        let trace = try XCTUnwrap(result.traceEvidence)

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.message, "dismissed")
        XCTAssertEqual(result.screenActionHandler, handler)
        XCTAssertEqual(trace.completeness, .complete)
        // The trace is the readings that found something new, in order. The
        // quiet reading that let the run settle is a stillness tick carrying no
        // capture, so it proves the run ended without adding a duplicate of the
        // tree it already recorded.
        XCTAssertEqual(
            trace.trace.captures.map(\.interface),
            [baseline, observed.changed].map(\.moment.capture.interface)
        )
        XCTAssertEqual(result.evidence.settlement, .settled(duration: 25))
        // Execution timing is measured by the executor against a real clock, so a
        // run driven by the reducer alone reports none rather than a stand-in.
        XCTAssertNil(result.timing?.beforeObservationMs)
        XCTAssertNil(result.timing?.finalSemanticEvidenceMs)
    }

    func testTypeTextPayloadRefreshesFromExactHandoffElement() async throws {
        let selectedId: HeistId = "selected_message"
        let baseline = await commit(label: "Baseline")
        let observed = await commitSettling(.makeForTests(elements: [
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
            action(
                command,
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
        let result = action(
            .dismiss,
            dispatch: dispatch,
            baseline: baseline,
            observed: nil,
            elapsed: 4
        )

        let projection = Settlement.ResultProjector.projectAction(result)

        XCTAssertNil(projection.expectation)
        XCTAssertEqual(projection.result?.outcome, .failure(.elementNotFound))
        XCTAssertEqual(projection.result?.message, "target disappeared")
    }

    func testBaselineUnavailableProjectsTypedTreeFailure() throws {
        let predicate = try predicate(.exists(.label("Ready")))
        let wait = scriptedSettlement(
            .observation(
                predicate: predicate,
                deadline: .init(phase: .observation, instant: .now),
                baseline: .unavailable(.unavailable)
            ),
            observation: nil,
            dispatch: .success(payload: .dismiss),
            elapsed: 0
        )

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
        let observed = await commitSettling(.makeForTests(elements: [
            (candidate, HeistId(rawValue: "dismiss_banner")),
        ]))
        let predicate = try predicate(.exists(.label("Ticket saved.")))
        let settlement = wait(
            predicate: predicate,
            baseline: baseline,
            observed: observed
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
        let result = scriptedSettlement(
            .action(actionCommand(.dismiss, baseline: baseline)),
            observation: nil,
            dispatch: .success(payload: .dismiss),
            cancelled: true,
            elapsed: 125
        )

        let action = try XCTUnwrap(
            Settlement.ResultProjector.projectAction(result).result
        )
        let trace = try XCTUnwrap(action.traceEvidence)

        XCTAssertEqual(action.outcome, .failure(.actionFailed))
        XCTAssertEqual(action.message, "cancelled after 125ms")
        XCTAssertEqual(action.evidence.settlement, .timedOut(duration: 125))
        XCTAssertNil(action.timing?.beforeObservationMs)
        XCTAssertEqual(trace.completeness, .incomplete)
        XCTAssertEqual(trace.trace.captures, [baseline.moment.capture])
    }
    func predicate(_ authored: AccessibilityPredicate) throws -> Settlement.Predicate {
        Settlement.Predicate(
            authored: authored,
            resolved: try authored.resolve(in: HeistExecutionEnvironment())
        )
    }

    /// A wait run to its terminal result by the real reducer.
    ///
    /// Whether it settled or timed out is not a parameter: the predicate either
    /// drains on `observed` or it does not, and settlement decides. Driving the
    /// reducer means the trace, handoff and tick log are whatever it produced,
    /// not a second version assembled here.
    func wait(
        predicate: Settlement.Predicate,
        baseline: Observation.SnapshotEvent,
        observed: Reading?,
        elapsed: ElapsedMilliseconds = RuntimeElapsed.admit(milliseconds: 25)
    ) -> Settlement.Result {
        scriptedSettlement(
            .observation(
                predicate: predicate,
                deadline: .init(phase: .observation, instant: .now),
                baseline: .supplied(.init(moment: baseline.moment))
            ),
            observation: observed?.changed,
            settling: observed?.settled,
            dispatch: .success(payload: .dismiss),
            elapsed: elapsed
        )
    }

    /// An action run to its terminal result by the real reducer.
    func action(
        _ command: ResolvedHeistActionCommand,
        dispatch: TheSafecracker.ActionDispatchResult,
        baseline: Observation.SnapshotEvent,
        observed: Reading?,
        elapsed: ElapsedMilliseconds = RuntimeElapsed.admit(milliseconds: 25)
    ) -> Settlement.Result {
        scriptedSettlement(
            .action(actionCommand(command, baseline: baseline)),
            observation: observed?.changed,
            settling: observed?.settled,
            dispatch: dispatch,
            elapsed: elapsed
        )
    }

    func waitCommand(
        _ predicate: Settlement.Predicate,
        baseline: Observation.SnapshotEvent
    ) -> Settlement.Command {
        .observation(
            predicate: predicate,
            deadline: .init(phase: .observation, instant: .now),
            baseline: .supplied(.init(moment: baseline.moment))
        )
    }

    func actionCommand(
        _ command: ResolvedHeistActionCommand,
        baseline: Observation.SnapshotEvent
    ) -> Settlement.Command.Action {
        Settlement.Command.Action(
            command: command,
            predicate: nil,
            allowances: .init(readiness: .seconds(5), expectation: nil),
            baseline: .supplied(.init(moment: baseline.moment))
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
            observationBoundary: .including(event.moment)
        )
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
