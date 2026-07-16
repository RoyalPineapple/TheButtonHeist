#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    func executeWaitStep(
        _ step: WaitStep,
        index: Int,
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        // A wait is a step with no command: just the predicate wait.
        await executeStep(
            .wait(step, scope: scope),
            index: index,
            path: path,
            start: start,
            runtime: runtime,
            environment: environment
        )
    }
}

struct HeistWaitReceipt {
    let actionResult: ActionResult
    let expectation: ExpectationResult
    let observedSequence: SettledObservationSequence?
    let observationSummary: String?

    var message: String? { actionResult.message }
    var traceEvidence: AccessibilityTraceEvidence? { actionResult.traceEvidence }

    var succeeded: Bool {
        actionResult.outcome.isSuccess && expectation.met
    }

    private init(
        actionResult: ActionResult,
        expectation: ExpectationResult,
        observedSequence: SettledObservationSequence?,
        observationSummary: String?
    ) {
        self.actionResult = actionResult
        self.expectation = expectation
        self.observedSequence = observedSequence
        self.observationSummary = observationSummary
    }

    static func matched(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Met,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil,
        announcement: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(
            actionResult: makeActionResult(
                errorKind: nil,
                message: message,
                traceEvidence: traceEvidence,
                announcement: announcement
            ),
            expectation: expectation.result,
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )
    }

    static func timedOut(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(
            actionResult: makeActionResult(
                errorKind: .timeout,
                message: message,
                traceEvidence: traceEvidence,
                announcement: nil
            ),
            expectation: expectation.result,
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )
    }

    static func failed(
        errorKind: ErrorKind,
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        announcement: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(
            actionResult: makeActionResult(
                errorKind: errorKind,
                message: message,
                traceEvidence: traceEvidence,
                announcement: announcement
            ),
            expectation: expectation.result,
            observedSequence: nil,
            observationSummary: nil
        )
    }

    private static func makeActionResult(
        errorKind: ErrorKind?,
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        announcement: String?
    ) -> ActionResult {
        let observation: ActionResultObservationEvidence
        switch (traceEvidence, announcement) {
        case (nil, nil):
            observation = .none
        case (nil, let announcement?):
            observation = .announcement(announcement)
        case (let evidence?, nil):
            observation = .trace(evidence)
        case (let evidence?, let announcement?):
            precondition(
                evidence.trace.capturedAnnouncements.first?.text == announcement,
                "wait announcement must belong to its accessibility trace"
            )
            observation = .trace(evidence)
        }
        if let errorKind {
            return ActionResult.failure(
                method: .wait,
                errorKind: errorKind,
                message: message,
                evidence: ActionResultFailureEvidence(observation: observation)
            )
        } else {
            return ActionResult.success(
                method: .wait,
                message: message,
                evidence: ActionResultSuccessEvidence(observation: observation)
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
