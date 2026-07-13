#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    func executeWaitStep(
        _ step: WaitStep,
        index: Int,
        path: String,
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
    enum Status {
        case matched
        case timedOut
        case failed(ErrorKind)

        var succeeded: Bool {
            guard case .matched = self else { return false }
            return true
        }

        var errorKind: ErrorKind? {
            switch self {
            case .matched:
                return nil
            case .timedOut:
                return .timeout
            case .failed(let errorKind):
                return errorKind
            }
        }
    }

    struct MatchedEvidence {
        let message: String?
        let traceEvidence: AccessibilityTraceEvidence?
        let expectation: ExpectationResult.Met
        let observedSequence: SettledObservationSequence?
        let observationSummary: String?
        let announcement: String?
    }

    struct TimedOutEvidence {
        let message: String?
        let traceEvidence: AccessibilityTraceEvidence?
        let expectation: ExpectationResult.Unmet
        let observedSequence: SettledObservationSequence?
        let observationSummary: String?
    }

    struct FailedEvidence {
        let errorKind: ErrorKind
        let message: String?
        let traceEvidence: AccessibilityTraceEvidence?
        let expectation: ExpectationResult.Unmet
        let announcement: String?
    }

    enum Outcome {
        case matched(MatchedEvidence)
        case timedOut(TimedOutEvidence)
        case failed(FailedEvidence)
    }

    let outcome: Outcome

    var status: Status {
        switch outcome {
        case .matched:
            return .matched
        case .timedOut:
            return .timedOut
        case .failed(let evidence):
            return .failed(evidence.errorKind)
        }
    }

    var message: String? {
        switch outcome {
        case .matched(let evidence):
            return evidence.message
        case .timedOut(let evidence):
            return evidence.message
        case .failed(let evidence):
            return evidence.message
        }
    }

    var traceEvidence: AccessibilityTraceEvidence? {
        switch outcome {
        case .matched(let evidence):
            return evidence.traceEvidence
        case .timedOut(let evidence):
            return evidence.traceEvidence
        case .failed(let evidence):
            return evidence.traceEvidence
        }
    }

    var accessibilityTrace: AccessibilityTrace? { traceEvidence?.trace }

    var expectation: ExpectationResult {
        switch outcome {
        case .matched(let evidence):
            return evidence.expectation.result
        case .timedOut(let evidence):
            return evidence.expectation.result
        case .failed(let evidence):
            return evidence.expectation.result
        }
    }

    var observedSequence: SettledObservationSequence? {
        switch outcome {
        case .matched(let evidence):
            return evidence.observedSequence
        case .timedOut(let evidence):
            return evidence.observedSequence
        case .failed:
            return nil
        }
    }

    var observationSummary: String? {
        switch outcome {
        case .matched(let evidence):
            return evidence.observationSummary
        case .timedOut(let evidence):
            return evidence.observationSummary
        case .failed:
            return nil
        }
    }

    var announcement: String? {
        switch outcome {
        case .matched(let evidence):
            return evidence.announcement
        case .timedOut:
            return nil
        case .failed(let evidence):
            return evidence.announcement
        }
    }

    var actionResult: ActionResult {
        makeActionResult()
    }

    var succeeded: Bool {
        status.succeeded
    }

    static func matched(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Met,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil,
        announcement: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(outcome: .matched(MatchedEvidence(
            message: message,
            traceEvidence: traceEvidence,
            expectation: expectation,
            observedSequence: observedSequence,
            observationSummary: observationSummary,
            announcement: announcement
        )))
    }

    static func timedOut(
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(outcome: .timedOut(TimedOutEvidence(
            message: message,
            traceEvidence: traceEvidence,
            expectation: expectation,
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )))
    }

    static func failed(
        errorKind: ErrorKind,
        message: String?,
        traceEvidence: AccessibilityTraceEvidence?,
        expectation: ExpectationResult.Unmet,
        announcement: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(outcome: .failed(FailedEvidence(
            errorKind: errorKind,
            message: message,
            traceEvidence: traceEvidence,
            expectation: expectation,
            announcement: announcement
        )))
    }

    func makeActionResult(method: ActionMethod = .wait) -> ActionResult {
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
        switch status {
        case .matched:
            return ActionResult.success(
                method: method,
                message: message,
                evidence: ActionResultSuccessEvidence(observation: observation)
            )
        case .timedOut:
            return ActionResult.failure(
                method: method,
                errorKind: .timeout,
                message: message,
                evidence: ActionResultFailureEvidence(observation: observation)
            )
        case .failed(let errorKind):
            return ActionResult.failure(
                method: method,
                errorKind: errorKind,
                message: message,
                evidence: ActionResultFailureEvidence(observation: observation)
            )
        }
    }
}

extension HeistWaitReceipt.Status: Equatable {
    static func == (lhs: HeistWaitReceipt.Status, rhs: HeistWaitReceipt.Status) -> Bool {
        switch (lhs, rhs) {
        case (.matched, .matched), (.timedOut, .timedOut):
            return true
        case (.failed(let lhsKind), .failed(let rhsKind)):
            return lhsKind == rhsKind
        case (.matched, _), (.timedOut, _), (.failed, _):
            return false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
