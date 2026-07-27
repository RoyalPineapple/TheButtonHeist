#if canImport(UIKit)
#if DEBUG
import XCTest

@testable import TheInsideJob
@testable import ThePlans
@testable import TheScore

@MainActor
final class SettlementTerminalLogTests: SemanticObservationStreamTestCase {
    func testCurrentStateResultsRenderTerminalTruth() async {
        let event = await commit(label: "Current")

        assertLog(
            .currentState(.captured(.init(
                event: event,
                timing: timing
            ))),
            contains: [
                "command=currentState",
                "observation=\(event.sequence.rawValue)",
                "outcome=settled",
                "elapsedMs=25",
            ]
        )
        assertLog(
            .currentState(.failed(.init(
                reason: .unavailable(.admissionRejected),
                timing: timing
            ))),
            contains: [
                "command=currentState",
                "observation=none",
                // A currentState capture never arms, so it has no baseline to be
                // missing: what failed is the capture. Only observation and
                // action can report `baselineUnavailable`.
                "outcome=failed(admissionRejected)",
            ]
        )
    }

    func testObservationResultsRenderEvaluationAndHandoffTruth() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commitSettling(label: "Observed")

        // A predicate the observation answers settles; one it does not runs out
        // of time. Which happens is the reducer's call, not the fixture's.
        // Both name the newest reading the run admitted, which is the quiet one
        // that let it settle.
        assertLog(
            wait(.elementsChanged, baseline: baseline, observed: observed),
            contains: [
                "command=observation",
                "predicate=satisfied",
                "observation=\(observed.settled.sequence.rawValue)",
                "handoff=admitted(observation=\(observed.settled.sequence.rawValue))",
                "outcome=settled",
            ]
        )

        let unmet = try predicate(.exists(.label("Never")))
        assertLog(
            wait(unmet.authored, baseline: baseline, observed: observed),
            contains: [
                "command=observation",
                // Names the outstanding predicate, not just that one exists: the
                // tip of the list is what the run was blocked on.
                "predicate=waiting(\(try XCTUnwrap(Expectation([unmet.resolved]).outstanding.first).description))",
                "observation=\(observed.settled.sequence.rawValue)",
                "outcome=timedOut(observation)",
            ]
        )
    }

    func testActionResultsRenderDispatchTruth() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commitSettling(label: "Observed")

        // An action with no predicate settles on its handoff, which is taken at
        // readiness — so the row names the reading that established it rather
        // than the quiet one a waiting run would have needed.
        assertLog(
            action(dispatch: .success(payload: .dismiss), baseline: baseline, observed: observed),
            contains: [
                "command=action",
                "predicate=notRequired",
                "dispatch=succeeded",
                "observation=\(observed.changed.sequence.rawValue)",
                "handoff=admitted(observation=\(observed.changed.sequence.rawValue))",
                "outcome=settled",
            ]
        )

        // A dispatch that failed ends the run before any observation arrives,
        // so the row has no observation to name.
        assertLog(
            action(
                dispatch: .failure(.dismiss, message: "Dismiss failed", failureKind: .actionFailed),
                baseline: baseline,
                observed: nil
            ),
            contains: [
                "command=action",
                "predicate=notRequired",
                "dispatch=failed(actionFailed)",
                "observation=none",
                "outcome=dispatchFailed",
            ]
        )
    }

    /// A wait run to its terminal result by the real reducer.
    private func wait(
        _ authored: AccessibilityPredicate,
        baseline: Observation.SnapshotEvent,
        observed: Reading?
    ) -> Settlement.Result {
        scriptedSettlement(
            .observation(
                predicate: .init(authored: authored, resolved: resolved(authored)),
                deadline: .init(phase: .observation, instant: .now),
                baseline: .supplied(.init(moment: baseline.moment))
            ),
            observation: observed?.changed,
            settling: observed?.settled,
            dispatch: .success(payload: .dismiss),
            elapsed: 25
        )
    }

    /// An action run to its terminal result by the real reducer.
    private func action(
        dispatch: TheSafecracker.ActionDispatchResult,
        baseline: Observation.SnapshotEvent,
        observed: Reading?
    ) -> Settlement.Result {
        scriptedSettlement(
            .action(.init(
                command: .dismiss,
                predicate: nil,
                allowances: .init(readiness: .seconds(5), expectation: nil),
                baseline: .supplied(.init(moment: baseline.moment))
            )),
            observation: observed?.changed,
            settling: observed?.settled,
            dispatch: dispatch,
            elapsed: 25
        )
    }

    private func predicate(
        _ authored: AccessibilityPredicate
    ) throws -> Settlement.Predicate {
        .init(authored: authored, resolved: try authored.resolve(in: .empty))
    }

    private func resolved(
        _ authored: AccessibilityPredicate
    ) -> ResolvedAccessibilityPredicate {
        guard let resolved = try? authored.resolve(in: .empty) else {
            preconditionFailure("Test predicate must resolve")
        }
        return resolved
    }

    private var timing: Settlement.Result.Timing {
        .init(execution: .init(), elapsed: 25)
    }

    private var observationPredicate: Settlement.Predicate {
        .init(
            authored: .elementsChanged,
            resolved: .elementsChanged([])
        )
    }

    private func readiness(
        for event: Observation.SnapshotEvent
    ) -> Settlement.Readiness.Establishment {
        .init(
            generation: .initial,
            observationBoundary: .including(event.moment)
        )
    }

    private func commit(label: String) async -> Observation.SnapshotEvent {
        await vault.semanticObservationStream.commitVisibleObservationForTesting(
            observation(label: label, heistId: HeistId(rawValue: label.lowercased()))
        )
    }

    private func assertLog(
        _ result: Settlement.Result,
        contains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rendered = Settlement.TerminalLog.render(result)
        for fragment in fragments {
            XCTAssertTrue(
                rendered.contains(fragment),
                "\(rendered) does not contain \(fragment)",
                file: file,
                line: line
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
