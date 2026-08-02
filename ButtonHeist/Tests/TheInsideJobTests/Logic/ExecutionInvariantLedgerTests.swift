#if canImport(UIKit)
#if DEBUG
import ButtonHeistTestSupport
import Foundation
import Testing

@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

// Finite execution ledger:
// - completed execution is absorbing — `completed action absorbs late events and cancellation`.
// - stale wait identities cannot advance a later leaf —
//   `stale deadline and effect events cannot advance a later leaf`.
// - every action settles through authored expectation or waiver, then noChange —
//   `DeterministicRuntimeScenarioDriverTests`.
// - deadline equality and leaf-versus-whole precedence —
//   `DeterministicRuntimeScenarioDriverTests`.
// - caller cancellation has one absorbing cleanup path —
//   `cancellation during observation close closes it once` and
//   `cancellation before failure capture is terminal and absorbing`.

@Suite struct ExecutionInvariantLedgerTests {
    @Test func `completed action absorbs late events and cancellation`() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
        ])
        var execution = try HeistExecution(plan: plan)
        let now = ContinuousClock.now

        guard case .perform(.beginObservation(let observationID, _, _)) = execution.start(
            at: now,
            timeout: try .seconds(60)
        ) else {
            Issue.record("Invariant violated: an action must request observation before dispatch")
            return
        }
        guard case .perform(.dispatch(let dispatchID, _, _)) = execution.reduce(
            .observationBegan(observationID, baseline: nil, at: now)
        ) else {
            Issue.record("Invariant violated: an observed action must request one dispatch")
            return
        }
        guard case .wait(let eventWait) = execution.reduce(.dispatchCompleted(
            dispatchID,
            .success(payload: .dismiss),
            at: now
        )) else {
            Issue.record("Invariant violated: an accepted dispatch must await settlement")
            return
        }
        guard case .perform(.sampleObservationClose(let closeID, let finishedObservationID, _, _, _)) = execution.reduce(
            .observation(eventWait.id, .noChange, at: now)
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
        guard case .perform(.commitObservationClose(let commitID, let committedObservationID)) = execution.reduce(.observationCloseSampled(
            closeID,
            source: .request,
            observationID: observationID,
            evidence: evidence,
            close: .init(captureAvailable: true, viewportExit: nil, lastTreeChangeAt: nil),
            at: now
        )), committedObservationID == observationID,
              case .complete(let completion) = execution.reduce(
                  .observationCloseCommitted(commitID, at: now)
              ) else {
            Issue.record("Invariant violated: complete action evidence must commit before completion")
            return
        }

        let lateEffect = execution.reduce(.dispatchCompleted(
            dispatchID,
            .failure(.dismiss, message: "late effect"),
            at: now
        ))
        let lateEvent = execution.reduce(.observation(eventWait.id, .noChange, at: now))
        let lateCancellation = execution.reduce(.cancellationRequested(at: now))

        guard case .complete(let afterLateEffect) = lateEffect,
              case .complete(let afterLateEvent) = lateEvent,
              case .complete(let afterLateCancellation) = lateCancellation else {
            Issue.record("Invariant violated: completed execution must remain terminal")
            return
        }
        #expect(afterLateEffect.steps == completion.steps)
        #expect(afterLateEvent.steps == completion.steps)
        #expect(afterLateCancellation.steps == completion.steps)
        #expect(afterLateCancellation.outcome == completion.outcome)
    }

    @Test func `cancellation during observation close closes it once`() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
        ])
        var execution = try HeistExecution(plan: plan)
        let now = ContinuousClock.now

        guard case .perform(.beginObservation(let observationID, _, _)) = execution.start(
            at: now,
            timeout: try .seconds(60)
        ),
              case .perform(.dispatch(let dispatchID, _, _)) = execution.reduce(
                  .observationBegan(observationID, baseline: nil, at: now)
              ),
              case .wait(let eventWait) = execution.reduce(.dispatchCompleted(
                  dispatchID,
                  .success(payload: .dismiss),
                  at: now
              )),
              case .perform(.sampleObservationClose(let closeID, let closingObservationID, _, _, _)) = execution.reduce(
                  .observation(eventWait.id, .noChange, at: now)
              ), closingObservationID == observationID else {
            Issue.record("Invariant violated: a settled action must request final observation evidence")
            return
        }

        guard case .perform(.cancelObservation(let cancellationID, let cancelledObservationID)) = execution.reduce(
            .cancellationRequested(at: now)
        ), cancelledObservationID == observationID else {
            Issue.record("Invariant violated: cancellation must close the active observation")
            return
        }

        let evidence = Observation.Evidence(
            baseline: nil,
            events: [.noChange],
            current: nil,
            coverage: .complete
        )
        guard case .perform(.cancelObservation(let retainedCancellationID, let retainedObservationID)) = execution.reduce(
            .observationCloseSampled(
                closeID,
                source: .request,
                observationID: observationID,
                evidence: evidence,
                close: .init(captureAvailable: true, viewportExit: nil, lastTreeChangeAt: nil),
                at: now
            )
        ), retainedCancellationID == cancellationID,
           retainedObservationID == cancelledObservationID else {
            Issue.record("Invariant violated: a late close sample must retain the one cancellation effect")
            return
        }

        guard case .complete(let completion) = execution.reduce(
            .cancellationCompleted(cancellationID, at: now)
        ) else {
            Issue.record("Invariant violated: acknowledged cancellation must terminate execution")
            return
        }
        #expect(completion.outcome == .cancelled)
    }

    @Test func `cancellation before failure capture is terminal and absorbing`() throws {
        let plan = try HeistPlan(body: [
            .fail(FailStep(message: try .init(validating: "expected failure"))),
        ])
        var execution = try HeistExecution(
            plan: plan,
            failureCaptureMode: .raw
        )
        let now = ContinuousClock.now

        guard case .perform(.captureFailureScreenshot(let captureID, _, _)) = execution.start(
            at: now,
            timeout: try .seconds(60)
        ) else {
            Issue.record("Invariant violated: a failed execution must request configured evidence")
            return
        }
        guard case .complete(let cancellation) = execution.reduce(
            .cancellationRequested(at: now)
        ) else {
            Issue.record("Invariant violated: cancellation must abandon optional failure evidence")
            return
        }
        guard case .complete(let afterLateCapture) = execution.reduce(
            .failureScreenshotCaptured(
                captureID,
                .unavailable(kind: .actionFailed, message: "late capture"),
                at: now
            )
        ) else {
            Issue.record("Invariant violated: cancelled execution must absorb late failure evidence")
            return
        }

        #expect(cancellation.outcome == .cancelled)
        #expect(cancellation.failureCapture == nil)
        #expect(afterLateCapture.outcome == .cancelled)
        #expect(afterLateCapture.failureCapture == nil)
    }

    @Test func `admitted failure capture wins before late cancellation`() throws {
        let plan = try HeistPlan(body: [
            .fail(FailStep(message: try .init(validating: "expected failure"))),
        ])
        var execution = try HeistExecution(
            plan: plan,
            failureCaptureMode: .raw
        )
        let now = ContinuousClock.now
        let capture = HeistFailureCapture.unavailable(
            kind: .actionFailed,
            message: "fixture capture unavailable"
        )

        guard case .perform(.captureFailureScreenshot(let captureID, _, _)) = execution.start(
            at: now,
            timeout: try .seconds(60)
        ),
              case .complete(let completed) = execution.reduce(
                  .failureScreenshotCaptured(captureID, capture, at: now)
              ),
              case .complete(let afterLateCancellation) = execution.reduce(
                  .cancellationRequested(at: now)
              ) else {
            Issue.record("Invariant violated: admitted failure evidence must complete execution")
            return
        }

        #expect(completed.outcome == .completed)
        #expect(completed.failureCapture == capture)
        #expect(afterLateCancellation.outcome == .completed)
        #expect(afterLateCancellation.failureCapture == capture)
    }

    @Test func `stale deadline and effect events cannot advance a later leaf`() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(predicate: .notification("First"), timeout: try .seconds(5))),
            .wait(WaitStep(predicate: .notification("Second"), timeout: try .seconds(5))),
        ])
        var execution = try HeistExecution(plan: plan)
        let now = ContinuousClock.now

        guard case .perform(.beginObservation(let firstObservationID, _, _)) = execution.start(
            at: now,
            timeout: try .seconds(60)
        ),
              case .wait(let firstWait) = execution.reduce(
                  .observationBegan(firstObservationID, baseline: nil, at: now)
              ),
              case .wait(let terminalWait) = execution.reduce(
                  .observation(firstWait.id, heistNotification("First"), at: now)
              ),
              case .perform(.sampleObservationClose(let firstCloseID, _, _, _, _)) = execution.reduce(
                  .observation(terminalWait.id, .noChange, at: now)
              ) else {
            Issue.record("Invariant violated: the first wait must request final evidence")
            return
        }

        let firstEvidence = Observation.Evidence(
            baseline: nil,
            events: [heistNotification("First"), .noChange],
            current: nil,
            coverage: .complete
        )
        guard case .perform(.commitObservationClose(let firstCommitID, let committedFirstObservationID)) = execution.reduce(
            .observationCloseSampled(
                firstCloseID,
                source: .request,
                observationID: firstObservationID,
                evidence: firstEvidence,
                close: .init(captureAvailable: true, viewportExit: nil, lastTreeChangeAt: nil),
                at: now
            )
        ), committedFirstObservationID == firstObservationID else {
            Issue.record("Invariant violated: satisfying evidence must request an observation-close commit")
            return
        }

        guard case .perform(.commitObservationClose(let retainedCommitID, _)) = execution.reduce(
            .observationCloseSampled(
                firstCloseID,
                source: .request,
                observationID: firstObservationID,
                evidence: firstEvidence,
                close: .init(captureAvailable: true, viewportExit: nil, lastTreeChangeAt: nil),
                at: now
            )
        ), retainedCommitID == firstCommitID else {
            Issue.record("Invariant violated: a stale close sample must retain the pending commit")
            return
        }

        guard case .perform(.beginObservation(let secondObservationID, _, _)) = execution.reduce(
            .observationCloseCommitted(firstCommitID, at: now)
        ) else {
            Issue.record("Invariant violated: satisfying one wait must begin the next leaf")
            return
        }

        guard case .perform(.beginObservation(let retainedSecondID, _, _)) = execution.reduce(
            .observationCloseCommitted(firstCommitID, at: now)
        ), retainedSecondID == secondObservationID else {
            Issue.record("Invariant violated: a stale observation-start effect must retain next leaf")
            return
        }

        guard case .wait(let secondWait) = execution.reduce(
            .observationBegan(secondObservationID, baseline: nil, at: now)
        ) else {
            Issue.record("Invariant violated: the second leaf must receive its own wait identity")
            return
        }
        guard case .wait(let retainedWait) = execution.reduce(
            .deadlineElapsed(firstWait.id, at: now)
        ) else {
            Issue.record("Invariant violated: a stale deadline must retain the active wait")
            return
        }
        #expect(retainedWait == secondWait)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
