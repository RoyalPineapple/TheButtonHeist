import ThePlans
import Foundation

// MARK: - Heist Report Facts
//
// Reporting consumes the execution tree directly. These derived facts live on
// the execution result types so encoders, formatters, and playback walk
// `HeistExecutionResult.steps` without a second report worldview.

/// Outcome status for a heist execution step in report and wire output.
public enum HeistStepStatus: String, Sendable {
    case passed
    case failed
    case skipped
    case warned
}

public extension HeistExecutionStepResult {
    /// Report status derived from the execution outcome.
    var reportStatus: HeistStepStatus {
        if isSkipped { return .skipped }
        if kind == .warn { return .warned }
        if isFailure { return .failed }
        return .passed
    }

    /// Wire-format step name. Disambiguates `for_each` into element/string from
    /// the execution path and renames `conditional` → `if`,
    /// `waitForCases` → `wait_for_cases`.
    var reportStepName: String {
        switch kind {
        case .action, .skipped:
            return "action"
        case .wait:
            return "wait"
        case .conditional:
            return "if"
        case .waitForCases:
            return "wait_for_cases"
        case .forEach:
            let isString = path.contains("for_each_string")
                || children.contains { $0.path.contains("for_each_string") }
            return isString ? "for_each_string" : "for_each_element"
        case .forEachElement:
            return "for_each_element"
        case .forEachString:
            return "for_each_string"
        case .forEachIteration:
            return "for_each_iteration"
        case .warn:
            return "warn"
        case .fail:
            return "fail"
        case .heist:
            return "heist"
        case .invoke:
            return "invoke"
        }
    }

    /// Wire message type for an action-kind step. Prefers the recorded command;
    /// falls back to the delivered action method.
    var reportClientWireType: ClientWireMessageType? {
        guard kind == .action else { return nil }
        if let actionCommand {
            return actionCommand.clientWireType
        }
        return actionResult?.method.heistReportWireType
            ?? expectationActionResult?.method.heistReportWireType
    }

    /// Wire command name for an action-kind step.
    var reportCommandName: String? {
        reportClientWireType?.rawValue
    }

    /// Durable matcher target for an action-kind step, if any.
    var reportTarget: ElementTarget? {
        actionCommand?.reportTarget
    }

    /// Message to surface for this step. A skip reason wins over the step's
    /// own message.
    var reportMessage: String? {
        skipped?.reason ?? message
    }

    /// Final action result for an action-kind step. An expectation re-check
    /// result wins over the original action result when present.
    var reportActionResult: ActionResult? {
        guard kind == .action else { return nil }
        return expectationActionResult ?? actionResult
    }

    /// Expectation to surface for this step, suppressed when the action itself
    /// failed (the action failure is the headline).
    var reportExpectation: ExpectationResult? {
        if reportActionResult?.success == false { return nil }
        return expectation
    }

    /// Number of expectations evaluated in this subtree.
    var expectationsChecked: Int {
        (reportExpectation?.predicate == nil ? 0 : 1)
            + children.reduce(0) { $0 + $1.expectationsChecked }
    }

    /// Number of evaluated expectations that were met in this subtree.
    var expectationsMet: Int {
        ((reportExpectation?.met == true && reportExpectation?.predicate != nil) ? 1 : 0)
            + children.reduce(0) { $0 + $1.expectationsMet }
    }

    /// Final action results in execution order across this subtree.
    var finalActionResultsInExecutionOrder: [ActionResult] {
        (reportActionResult.map { [$0] } ?? [])
            + children.flatMap(\.finalActionResultsInExecutionOrder)
    }

    /// Public-facing failure message for a failed or skipped step, derived from
    /// the execution outcome. Returns nil for passed/warned steps and for
    /// structural nodes whose failure is fully described by a failed child.
    var reportFailureMessage: String? {
        switch reportStatus {
        case .passed, .warned:
            return nil
        case .skipped, .failed:
            break
        }
        if children.contains(where: { $0.reportStatus == .failed }) {
            switch kind {
            case .conditional, .waitForCases, .forEachIteration, .heist, .invoke:
                return nil
            case .action, .wait, .forEach, .forEachElement, .forEachString, .warn, .fail, .skipped:
                break
            }
        }
        if let message {
            return message
        }
        if let action = reportActionResult, !action.success {
            return action.message ?? "action failed"
        }
        if let expectation = reportExpectation, !expectation.met {
            return expectation.actual ?? "expectation not met"
        }
        if kind == .waitForCases,
           caseSelection?.timedOut == true,
           caseSelection?.elseRan != true {
            return "wait_for_cases timed out"
        }
        if let reason = forEachResult?.failureReason {
            return reason
        }
        return "heist step failed"
    }
}

public extension HeistExecutionResult {
    /// Steps that actually ran (skipped steps excluded).
    var completedStepCount: Int {
        steps.count(where: { !$0.isSkipped })
    }

    /// Index of the step that stopped the heist, if any.
    var stoppedFailedIndex: Int? {
        failedIndex ?? steps.first { $0.stopsHeist }?.index
    }

    /// Total expectations evaluated across the whole execution tree.
    var expectationsChecked: Int {
        steps.reduce(0) { $0 + $1.expectationsChecked }
    }

    /// Total met expectations across the whole execution tree.
    var expectationsMet: Int {
        steps.reduce(0) { $0 + $1.expectationsMet }
    }

    /// Final action results in execution order across the whole tree.
    var finalActionResultsInExecutionOrder: [ActionResult] {
        steps.flatMap(\.finalActionResultsInExecutionOrder)
    }

    /// Steps flattened into report rows in execution order. `for_each` loops
    /// collapse to a single row; every other node recurses into its children.
    /// The flattened position is an output concern and must not drive runtime
    /// failure logic.
    var reportRows: [HeistExecutionStepResult] {
        Self.reportRows(steps)
    }

    private static func reportRows(_ steps: [HeistExecutionStepResult]) -> [HeistExecutionStepResult] {
        steps.flatMap { step -> [HeistExecutionStepResult] in
            switch step.kind {
            case .forEach, .forEachElement, .forEachString:
                return [step]
            case .action, .wait, .conditional, .waitForCases, .forEachIteration,
                 .warn, .fail, .heist, .invoke, .skipped:
                return [step] + reportRows(step.children)
            }
        }
    }
}

// MARK: - Action Method Wire Mapping

private extension ActionMethod {
    /// The client wire message type a delivered action method corresponds to,
    /// used to recover a command name when no recorded command is present.
    var heistReportWireType: ClientWireMessageType? {
        switch self {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .syntheticTap: return .oneFingerTap
        case .syntheticLongPress: return .longPress
        case .syntheticSwipe: return .swipe
        case .syntheticDrag: return .drag
        case .typeText: return .typeText
        case .customAction: return .performCustomAction
        case .editAction: return .editAction
        case .resignFirstResponder: return .resignFirstResponder
        case .setPasteboard: return .setPasteboard
        case .rotor: return .rotor
        case .scroll: return .scroll
        case .scrollToVisible: return .scrollToVisible
        case .scrollToEdge: return .scrollToEdge
        case .getPasteboard, .heistPlan, .wait:
            return nil
        }
    }
}
