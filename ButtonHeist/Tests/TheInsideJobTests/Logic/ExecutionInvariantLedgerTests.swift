#if canImport(UIKit)
#if DEBUG
import ButtonHeistTestSupport
import Testing

@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

// Finite execution ledger:
// - completed execution is absorbing — `completed action absorbs stale effect and event input`.
// - stale request and duplicate effect completion —
//   `HeistMachineStepExecutionTests.testStaleAndDuplicateDispatchCompletionsCannotAdvanceAction`.
// - every action settles through authored expectation or waiver, then noChange —
//   `HeistMachineStepExecutionTests.testAuthoredActionRequiresNoChangeAfterItsAuthoredExpectation`
//   and `testWaivedActionRequiresTerminalNoChangeBeforeFinishing`.
// - incomplete evidence cannot pass —
//   `HeistResultSemanticAdmissionTests.passed action evidence requires expectation replay proof`.
// - deadline equality and leaf-versus-whole precedence —
//   `HeistMachineExpectationTests.testSubstantiveEventDuringFinalCaptureReopensObservation`
//   and `HeistMachineControlFlowTests.testWaitElseDoesNotRunForHeistTimeoutCancellationOrUnavailableEvidence`.
// - cancellation is terminal — `HeistMachineStepExecutionTests.testCancelledActionIsTerminalFailure`.
// - Host scheduling races remain for the deterministic Host driver; live UIKit restoration remains hosted.

@Suite struct ExecutionInvariantLedgerTests {
    @Test func `completed action absorbs stale effect and event input`() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
        ])
        var machine = try HeistExecution.Machine(plan: plan)

        guard case .perform(.beginObservation(let observationID, _)) = machine.start() else {
            Issue.record("Invariant violated: an action must request observation before dispatch")
            return
        }
        guard case .perform(.dispatch(let dispatchID, _)) = machine.advance(
            .observationBegan(observationID, baseline: nil)
        ) else {
            Issue.record("Invariant violated: an observed action must request one dispatch")
            return
        }
        guard case .wait = machine.advance(.dispatchCompleted(
            dispatchID,
            .success(payload: .dismiss)
        )) else {
            Issue.record("Invariant violated: an accepted dispatch must await settlement")
            return
        }
        guard case .perform(.finishObservation(let finishID, let finishedObservationID, _)) = machine.advance(
            .event(.noChange)
        ), finishedObservationID == observationID else {
            Issue.record("Invariant violated: terminal noChange must request final action evidence")
            return
        }

        let evidence = Observation.Evidence(
            baseline: nil,
            events: [.noChange],
            current: nil,
            coverage: .complete
        )
        guard case .complete(let completion) = machine.advance(.observationFinished(
            source: .request(finishID),
            observationID: observationID,
            evidence: evidence,
            outcome: .completed,
            timing: HeistResultFixture.expectationTiming
        )) else {
            Issue.record("Invariant violated: complete action evidence must complete the machine")
            return
        }

        let lateEffect = machine.advance(.dispatchCompleted(
            dispatchID,
            .failure(.dismiss, message: "stale effect")
        ))
        let lateEvent = machine.advance(.event(.noChange))

        guard case .complete(let afterLateEffect) = lateEffect,
              case .complete(let afterLateEvent) = lateEvent else {
            Issue.record("Invariant violated: completed execution must remain terminal")
            return
        }
        #expect(afterLateEffect.steps == completion.steps)
        #expect(afterLateEvent.steps == completion.steps)
    }
}
#endif
#endif
