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
                "outcome=baselineUnavailable(admissionRejected)",
            ]
        )
    }

    func testObservationResultsRenderEvaluationAndHandoffTruth() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commit(label: "Observed")
        let predicate = observationPredicate
        let readiness = readiness(for: observed)
        let history = Observation.EventsSince.events([.snapshot(observed)])
        let handoff = try XCTUnwrap(Settlement.Handoff.Admission.admit(
            .init(event: observed, history: history),
            for: readiness
        ))
        let evaluation = Settlement.Predicate.EvaluationResponse(
            target: .observation(observed.moment),
            result: .init(met: true, actual: "Observed")
        )

        assertLog(
            .observation(.settled(.init(
                predicate: predicate,
                boundary: .init(moment: baseline.moment),
                evaluation: evaluation,
                readiness: readiness,
                handoff: handoff,
                history: history,
                timing: timing
            ))),
            contains: [
                "command=observation",
                "predicate=satisfied(observation:\(observed.sequence.rawValue))",
                "observation=\(observed.sequence.rawValue)",
                "handoff=admitted(observation:\(observed.sequence.rawValue))",
                "outcome=settled",
            ]
        )
        assertLog(
            .observation(.failed(.init(
                reason: .timedOut(.observation),
                attempt: .init(
                    predicate: predicate,
                    boundary: .established(.init(moment: baseline.moment)),
                    evaluation: .init(predicate: predicate),
                    readiness: .pending(.initial),
                    handoff: .pending(.initial),
                    history: history,
                    timing: timing
                )
            ))),
            contains: [
                "command=observation",
                "predicate=pending",
                "observation=\(observed.sequence.rawValue)",
                "outcome=timedOut(observation)",
            ]
        )
    }

    func testActionResultsRenderDispatchTruth() async throws {
        let baseline = await commit(label: "Baseline")
        let observed = await commit(label: "Observed")
        let readiness = readiness(for: observed)
        let history = Observation.EventsSince.events([.snapshot(observed)])
        let handoff = try XCTUnwrap(Settlement.Handoff.Admission.admit(
            .init(event: observed, history: history),
            for: readiness
        ))
        let command = Settlement.Command.Action(
            command: .dismiss,
            predicate: nil,
            allowances: .init(readiness: .seconds(5), expectation: nil),
            baseline: .capture
        )

        assertLog(
            .action(.settled(.init(
                command: command,
                boundary: .init(moment: baseline.moment),
                dispatch: .success(payload: .dismiss),
                evaluation: nil,
                readiness: readiness,
                handoff: handoff,
                history: history,
                timing: timing
            ))),
            contains: [
                "command=action",
                "predicate=notRequired",
                "dispatch=succeeded",
                "observation=\(observed.sequence.rawValue)",
                "outcome=settled",
            ]
        )
        assertLog(
            .action(.failed(.init(
                reason: .dispatchFailed,
                attempt: .init(
                    command: command,
                    boundary: .established(.init(moment: baseline.moment)),
                    dispatch: .completed(.failure(
                        .dismiss,
                        message: "Dismiss failed",
                        failureKind: .actionFailed
                    )),
                    evaluation: .init(predicate: nil),
                    readiness: .pending(.initial),
                    handoff: .pending(.initial),
                    history: nil,
                    timing: timing
                )
            ))),
            contains: [
                "command=action",
                "predicate=notRequired",
                "dispatch=failed(actionFailed)",
                "observation=none",
                "outcome=dispatchFailed",
            ]
        )
    }

    private var timing: Settlement.Result.Timing {
        .init(execution: .init(), elapsed: 25)
    }

    private var observationPredicate: Settlement.Predicate {
        .init(
            authored: .changed(.elements()),
            resolved: .changed(.elements([]))
        )
    }

    private func readiness(
        for event: Observation.SnapshotEvent
    ) -> Settlement.Readiness.Establishment {
        .init(
            generation: .initial,
            path: .semanticStability,
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
