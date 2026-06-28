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
        runtime: any HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        // A wait is a step with no command: just the predicate wait.
        await executeStep(
            command: nil,
            wait: step,
            index: index,
            path: path,
            start: start,
            runtime: runtime,
            environment: environment,
            scope: scope
        )
    }
}

struct HeistWaitOutcome {
    enum Status {
        case matched
        case timedOut
        case failed(ErrorKind?)

        init(actionResult: ActionResult) {
            if actionResult.success {
                self = .matched
            } else if actionResult.errorKind == .timeout {
                self = .timedOut
            } else {
                self = .failed(actionResult.errorKind)
            }
        }

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

    let status: Status
    let message: String?
    let accessibilityTrace: AccessibilityTrace?
    let expectation: ExpectationResult
    let observedSequence: SettledObservationSequence?
    let observationSummary: String?

    var succeeded: Bool {
        status.succeeded
    }

    init(
        status: Status,
        message: String?,
        accessibilityTrace: AccessibilityTrace?,
        expectation: ExpectationResult,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil
    ) {
        self.status = status
        self.message = message
        self.accessibilityTrace = accessibilityTrace
        self.expectation = expectation
        self.observedSequence = observedSequence
        self.observationSummary = observationSummary
    }

    init(
        actionResult: ActionResult,
        expectation: ExpectationResult,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil
    ) {
        self.init(
            status: Status(actionResult: actionResult),
            message: actionResult.message,
            accessibilityTrace: actionResult.accessibilityTrace,
            expectation: expectation,
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )
    }

    func actionResult(method: ActionMethod = .wait) -> ActionResult {
        ActionResult(
            success: succeeded,
            method: method,
            message: message,
            errorKind: status.errorKind,
            accessibilityTrace: accessibilityTrace
        )
    }
}

struct HeistWaitReceipt {
    let actionResult: ActionResult
    let waitOutcome: HeistWaitOutcome
    let expectation: ExpectationResult
    let observedSequence: SettledObservationSequence?
    let observationSummary: String?

    init(
        actionResult: ActionResult,
        expectation: ExpectationResult,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil
    ) {
        self.actionResult = actionResult
        self.waitOutcome = HeistWaitOutcome(
            actionResult: actionResult,
            expectation: expectation,
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )
        self.expectation = expectation
        self.observedSequence = observedSequence
        self.observationSummary = observationSummary
    }

    init(waitOutcome: HeistWaitOutcome) {
        self.actionResult = waitOutcome.actionResult()
        self.waitOutcome = waitOutcome
        self.expectation = waitOutcome.expectation
        self.observedSequence = waitOutcome.observedSequence
        self.observationSummary = waitOutcome.observationSummary
    }
}

extension HeistWaitOutcome.Status: Equatable {
    static func == (lhs: HeistWaitOutcome.Status, rhs: HeistWaitOutcome.Status) -> Bool {
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
