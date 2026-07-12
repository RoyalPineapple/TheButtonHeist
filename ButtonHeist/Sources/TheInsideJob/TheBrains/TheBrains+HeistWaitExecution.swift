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
        let accessibilityTrace: AccessibilityTrace?
        let expectation: ExpectationResult
        let observedSequence: SettledObservationSequence?
        let observationSummary: String?
        let announcement: String?
    }

    struct TimedOutEvidence {
        let message: String?
        let accessibilityTrace: AccessibilityTrace?
        let expectation: ExpectationResult
        let observedSequence: SettledObservationSequence?
        let observationSummary: String?
    }

    struct FailedEvidence {
        let errorKind: ErrorKind
        let message: String?
        let accessibilityTrace: AccessibilityTrace?
        let expectation: ExpectationResult
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

    var accessibilityTrace: AccessibilityTrace? {
        switch outcome {
        case .matched(let evidence):
            return evidence.accessibilityTrace
        case .timedOut(let evidence):
            return evidence.accessibilityTrace
        case .failed(let evidence):
            return evidence.accessibilityTrace
        }
    }

    var expectation: ExpectationResult {
        switch outcome {
        case .matched(let evidence):
            return evidence.expectation
        case .timedOut(let evidence):
            return evidence.expectation
        case .failed(let evidence):
            return evidence.expectation
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
        accessibilityTrace: AccessibilityTrace?,
        expectation: ExpectationResult,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil,
        announcement: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(outcome: .matched(MatchedEvidence(
            message: message,
            accessibilityTrace: accessibilityTrace,
            expectation: expectation,
            observedSequence: observedSequence,
            observationSummary: observationSummary,
            announcement: announcement
        )))
    }

    static func timedOut(
        message: String?,
        accessibilityTrace: AccessibilityTrace?,
        expectation: ExpectationResult,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(outcome: .timedOut(TimedOutEvidence(
            message: message,
            accessibilityTrace: accessibilityTrace,
            expectation: expectation,
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )))
    }

    static func failed(
        errorKind: ErrorKind,
        message: String?,
        accessibilityTrace: AccessibilityTrace?,
        expectation: ExpectationResult,
        announcement: String? = nil
    ) -> HeistWaitReceipt {
        HeistWaitReceipt(outcome: .failed(FailedEvidence(
            errorKind: errorKind,
            message: message,
            accessibilityTrace: accessibilityTrace,
            expectation: expectation,
            announcement: announcement
        )))
    }

    func makeActionResult(method: ActionMethod = .wait) -> ActionResult {
        switch status {
        case .matched:
            return ActionResult.success(
                method: method,
                message: message,
                accessibilityTrace: accessibilityTrace,
                announcement: announcement
            )
        case .timedOut:
            return ActionResult.failure(
                method: method,
                errorKind: .timeout,
                message: message,
                accessibilityTrace: accessibilityTrace,
                announcement: announcement
            )
        case .failed(let errorKind):
            return ActionResult.failure(
                method: method,
                errorKind: errorKind,
                message: message,
                accessibilityTrace: accessibilityTrace,
                announcement: announcement
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
