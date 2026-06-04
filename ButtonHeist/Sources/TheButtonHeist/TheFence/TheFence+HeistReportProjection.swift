import Foundation

@_spi(ButtonHeistInternals) import TheScore

/// Projects a heist plan and its execution result into the structured report
/// tree used by public JSON and report adapters.
///
/// The projection describes what execution already produced. It does not run
/// steps, evaluate predicates, resolve targets, or decide admission.
struct HeistReportProjection {
    let summary: HeistReportSummary
    let nodes: [HeistReportNode]

    init(plan _: HeistPlan, result: HeistExecutionResult) {
        self.nodes = result.steps.map(Self.node(outcome:))
        self.summary = HeistReportSummary(result: result, nodes: nodes)
    }

    var finalActionResultsInExecutionOrder: [ActionResult] {
        nodes.flatMap(\.finalActionResultsInExecutionOrder)
    }

    var finalActionProjectionsInExecutionOrder: [PublicActionProjection] {
        nodes.flatMap(\.finalActionProjectionsInExecutionOrder)
    }

    var compactLines: [PublicHeistReportLineProjection] {
        Self.compactLineNodes(from: nodes)
            .enumerated()
            .map { index, line in
                PublicHeistReportLineProjection(index: index, depth: line.depth, node: line.node)
            }
    }

    private static func node(outcome: HeistExecutionStepResult) -> HeistReportNode {
        let kind = HeistReportStepKind(outcome: outcome)
        return HeistReportNode(
            path: outcome.path,
            kind: kind,
            status: HeistReportStepStatus(outcome: outcome),
            message: outcome.skipped?.reason ?? outcome.message,
            durationMs: outcome.durationMs,
            action: actionProjection(for: outcome),
            expectation: outcome.expectation,
            caseSelection: outcome.caseSelection,
            forEachResult: outcome.forEachResult,
            children: outcome.children.map(Self.node(outcome:))
        )
    }

    private static func actionProjection(for outcome: HeistExecutionStepResult) -> HeistActionReportProjection? {
        guard outcome.kind == .action else { return nil }
        if let actionCommand = outcome.actionCommand {
            guard let fenceCommand = TheFence.Command(clientWireType: actionCommand.wireType) else {
                preconditionFailure("Missing Fence command for admitted heist action \(actionCommand.wireType.rawValue)")
            }
            return HeistActionReportProjection(
                commandName: actionCommand.wireType.rawValue,
                fenceCommand: fenceCommand,
                target: actionCommand.reportTarget,
                actionResult: outcome.actionResult,
                expectationActionResult: outcome.expectationActionResult
            )
        }
        guard let wireType = outcome.actionResult?.method.heistReportWireType
            ?? outcome.expectationActionResult?.method.heistReportWireType
        else {
            return nil
        }
        guard let fenceCommand = TheFence.Command(clientWireType: wireType) else {
            preconditionFailure("Missing Fence command for action result method \(wireType.rawValue)")
        }
        return HeistActionReportProjection(
            commandName: wireType.rawValue,
            fenceCommand: fenceCommand,
            target: nil,
            actionResult: outcome.actionResult,
            expectationActionResult: outcome.expectationActionResult
        )
    }

    private static func compactLineNodes(from nodes: [HeistReportNode]) -> [(node: HeistReportNode, depth: Int)] {
        nodes.flatMap { compactLineNodes(node: $0, depth: 0) }
    }

    private static func compactLineNodes(node: HeistReportNode, depth: Int) -> [(node: HeistReportNode, depth: Int)] {
        let row = (node: node, depth: depth)
        switch node.kind {
        case .forEachElement, .forEachString:
            return [row]
        case .action, .wait, .conditional, .waitForCases, .forEachIteration, .warn, .fail, .heist, .invoke:
            return [row] + node.children.flatMap { compactLineNodes(node: $0, depth: depth + 1) }
        }
    }
}

struct HeistReportSummary {
    let completedStepCount: Int
    let failedIndex: Int?
    let totalTimingMs: Int
    let expectationsChecked: Int
    let expectationsMet: Int

    init(result: HeistExecutionResult, nodes: [HeistReportNode]) {
        self.completedStepCount = result.completedStepCount
        self.failedIndex = result.stoppedFailedIndex
        self.totalTimingMs = result.totalTimingMs
        self.expectationsChecked = nodes.reduce(0) { $0 + $1.expectationsChecked }
        self.expectationsMet = nodes.reduce(0) { $0 + $1.expectationsMet }
    }
}

struct HeistReportNode {
    let path: String
    let kind: HeistReportStepKind
    let status: HeistReportStepStatus
    let message: String?
    let durationMs: Int
    let action: HeistActionReportProjection?
    let expectation: ExpectationResult?
    let caseSelection: HeistCaseSelectionResult?
    let forEachResult: HeistForEachResult?
    let children: [HeistReportNode]

    var expectationsChecked: Int {
        (expectationProjection?.expected == nil ? 0 : 1) + children.reduce(0) { $0 + $1.expectationsChecked }
    }

    var expectationsMet: Int {
        (expectationProjection?.met == true && expectationProjection?.expected != nil ? 1 : 0) +
            children.reduce(0) { $0 + $1.expectationsMet }
    }

    var expectationMet: Bool? {
        guard expectationProjection?.expected != nil else { return nil }
        return expectationProjection?.met
    }

    var expectationProjection: PublicExpectationProjection? {
        if action?.finalActionResult?.success == false {
            return nil
        }
        return expectation.map(PublicExpectationProjection.init(result:))
    }

    var finalActionResultsInExecutionOrder: [ActionResult] {
        [
            action?.finalActionResult,
        ].compactMap { $0 } + children.flatMap(\.finalActionResultsInExecutionOrder)
    }

    var finalActionProjectionsInExecutionOrder: [PublicActionProjection] {
        [
            action?.finalActionProjection,
        ].compactMap { $0 } + children.flatMap(\.finalActionProjectionsInExecutionOrder)
    }

    var publicFailureMessage: String? {
        switch status {
        case .passed, .warned:
            return nil
        case .skipped, .failed:
            break
        }
        if children.contains(where: { $0.status == .failed }) {
            switch kind {
            case .conditional, .waitForCases, .forEachIteration, .heist, .invoke:
                return nil
            case .action, .wait, .forEachElement, .forEachString, .warn, .fail:
                break
            }
        }
        if let message {
            return message
        }
        if let action = action?.finalActionProjection, action.status == .error {
            return action.message ?? "action failed"
        }
        if expectationProjection?.status == .failed {
            return expectationProjection?.actual ?? "expectation not met"
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

struct HeistActionReportProjection {
    let commandName: String
    let fenceCommand: TheFence.Command
    let target: ElementTarget?
    let actionResult: ActionResult?
    let expectationActionResult: ActionResult?

    var finalActionResult: ActionResult? {
        expectationActionResult ?? actionResult
    }

    var finalActionProjection: PublicActionProjection? {
        finalActionResult.map {
            PublicActionProjection(commandName: commandName, result: $0, expectation: nil)
        }
    }
}

enum HeistReportStepKind: String {
    case action
    case wait
    case conditional = "if"
    case waitForCases = "wait_for_cases"
    case forEachElement = "for_each_element"
    case forEachString = "for_each_string"
    case forEachIteration = "for_each_iteration"
    case warn
    case fail
    case heist
    case invoke

    init(outcome: HeistExecutionStepResult) {
        switch outcome.kind {
        case .action: self = .action
        case .wait: self = .wait
        case .conditional: self = .conditional
        case .waitForCases: self = .waitForCases
        case .forEach:
            self = outcome.path.contains("for_each_string") ||
                outcome.children.contains { $0.path.contains("for_each_string") }
                ? .forEachString
                : .forEachElement
        case .forEachElement: self = .forEachElement
        case .forEachString: self = .forEachString
        case .forEachIteration: self = .forEachIteration
        case .warn: self = .warn
        case .fail: self = .fail
        case .heist: self = .heist
        case .invoke: self = .invoke
        case .skipped: self = .action
        }
    }

    var reportName: String {
        rawValue
    }
}

enum HeistReportStepStatus: String {
    case passed
    case failed
    case skipped
    case warned

    init(outcome: HeistExecutionStepResult) {
        if outcome.skipped != nil {
            self = .skipped
        } else if outcome.kind == .warn {
            self = .warned
        } else if outcome.isFailure {
            self = .failed
        } else {
            self = .passed
        }
    }
}

extension HeistExecutionResult {
    var completedStepCount: Int {
        steps.count { !$0.isSkipped }
    }

    var stoppedFailedIndex: Int? {
        failedIndex ?? steps.first { $0.stopsHeist }?.index
    }
}

private extension ActionMethod {
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
