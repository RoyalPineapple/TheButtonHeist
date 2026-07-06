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

    let status: Status
    let message: String?
    let accessibilityTrace: AccessibilityTrace?
    let expectation: ExpectationResult
    let observedSequence: SettledObservationSequence?
    let observationSummary: String?
    let warning: HeistPredicateWarning?
    let announcement: String?

    var actionResult: ActionResult {
        makeActionResult()
    }

    var succeeded: Bool {
        status.succeeded
    }

    init(
        status: Status,
        message: String?,
        accessibilityTrace: AccessibilityTrace?,
        expectation: ExpectationResult,
        observedSequence: SettledObservationSequence? = nil,
        observationSummary: String? = nil,
        warning: HeistPredicateWarning? = nil,
        announcement: String? = nil
    ) {
        self.status = status
        self.message = message
        self.accessibilityTrace = accessibilityTrace
        self.expectation = expectation
        self.observedSequence = observedSequence
        self.observationSummary = observationSummary
        self.warning = warning
        self.announcement = announcement
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
