import Foundation

import TheScore

struct HeistReportProjection {
    let summary: HeistReportSummary
    let nodes: [HeistReportNode]

    init(plan: HeistPlan, result: HeistExecutionResult) {
        self.nodes = Self.nodes(
            steps: plan.steps,
            outcomes: result.steps,
            path: "$.steps"
        )
        self.summary = HeistReportSummary(result: result, nodes: nodes)
    }

    var legacyFlatRows: [HeistReportFlatRow] {
        nodes.flatMap(\.legacyFlatRows)
            .enumerated()
            .map { index, row in row.indexed(index) }
    }

    var finalActionResultsInExecutionOrder: [ActionResult] {
        nodes.flatMap(\.finalActionResultsInExecutionOrder)
    }

    private static func nodes(
        steps: [HeistStep],
        outcomes: [HeistExecutionStepResult],
        path: String,
        matchOutcomesByPosition: Bool = false
    ) -> [HeistReportNode] {
        steps.enumerated().compactMap { siblingIndex, step in
            let outcome: HeistExecutionStepResult?
            if matchOutcomesByPosition {
                outcome = outcomes[safe: siblingIndex]
            } else {
                outcome = outcomes.first { $0.index == siblingIndex }
            }
            guard let outcome else { return nil }
            return node(
                step: step,
                outcome: outcome,
                path: "\(path)[\(siblingIndex)]"
            )
        }
    }

    private static func node(
        step: HeistStep,
        outcome: HeistExecutionStepResult,
        path: String
    ) -> HeistReportNode {
        let kind = HeistReportStepKind(step: step)
        return HeistReportNode(
            path: path,
            kind: kind,
            status: HeistReportStepStatus(step: step, outcome: outcome),
            message: outcome.skipped?.reason ?? outcome.message,
            durationMs: outcome.durationMs,
            action: actionProjection(for: step, outcome: outcome),
            expectation: outcome.expectation,
            caseSelection: outcome.caseSelection,
            forEachResult: outcome.forEachResult,
            children: children(for: step, outcome: outcome, path: path)
        )
    }

    private static func actionProjection(
        for step: HeistStep,
        outcome: HeistExecutionStepResult
    ) -> HeistActionReportProjection? {
        guard case .action(let action) = step else { return nil }
        guard let fenceCommand = TheFence.Command(clientWireType: action.command.wireType) else {
            preconditionFailure("Missing Fence command for admitted heist action \(action.command.wireType.rawValue)")
        }
        return HeistActionReportProjection(
            commandName: action.command.wireType.rawValue,
            fenceCommand: fenceCommand,
            target: action.command.reportTarget,
            actionResult: outcome.actionResult,
            expectationActionResult: outcome.expectationActionResult
        )
    }

    private static func children(
        for step: HeistStep,
        outcome: HeistExecutionStepResult,
        path: String
    ) -> [HeistReportNode] {
        guard let childResults = outcome.childResults else { return [] }
        switch step {
        case .conditional(let conditional):
            if let selectedCaseIndex = outcome.caseSelection?.selectedCaseIndex,
               let selectedCase = conditional.cases[safe: selectedCaseIndex] {
                return nodes(
                    steps: selectedCase.steps,
                    outcomes: childResults,
                    path: "\(path).conditional.cases[\(selectedCaseIndex)].steps"
                )
            }
            if outcome.caseSelection?.elseRan == true {
                return nodes(
                    steps: conditional.elseSteps ?? [],
                    outcomes: childResults,
                    path: "\(path).conditional.else.steps"
                )
            }
            return []
        case .waitForCases(let waitForCases):
            if let selectedCaseIndex = outcome.caseSelection?.selectedCaseIndex,
               let selectedCase = waitForCases.cases[safe: selectedCaseIndex] {
                return nodes(
                    steps: selectedCase.steps,
                    outcomes: childResults,
                    path: "\(path).wait_for_cases.cases[\(selectedCaseIndex)].steps"
                )
            }
            if outcome.caseSelection?.elseRan == true {
                return nodes(
                    steps: waitForCases.elseSteps ?? [],
                    outcomes: childResults,
                    path: "\(path).wait_for_cases.else.steps"
                )
            }
            return []
        case .forEachElement(let forEach):
            return iterationNodes(
                kind: .forEachIteration,
                bodySteps: forEach.steps,
                childResults: childResults,
                path: "\(path).for_each_element.iterations"
            )
        case .forEachString(let forEach):
            return iterationNodes(
                kind: .forEachIteration,
                bodySteps: forEach.steps,
                childResults: childResults,
                path: "\(path).for_each_string.iterations"
            )
        case .action, .wait, .warn, .fail:
            return []
        }
    }

    private static func iterationNodes(
        kind: HeistReportStepKind,
        bodySteps: [HeistStep],
        childResults: [HeistExecutionStepResult],
        path: String
    ) -> [HeistReportNode] {
        guard !bodySteps.isEmpty, !childResults.isEmpty else { return [] }
        let bodyCount = bodySteps.count
        let iterationCount = Int(ceil(Double(childResults.count) / Double(bodyCount)))
        return (0..<iterationCount).map { iterationIndex in
            let lowerBound = iterationIndex * bodyCount
            let upperBound = min(lowerBound + bodyCount, childResults.count)
            let iterationResults = Array(childResults[lowerBound..<upperBound])
            let children = nodes(
                steps: bodySteps,
                outcomes: iterationResults,
                path: "\(path)[\(iterationIndex)].steps",
                matchOutcomesByPosition: true
            )
            let failed = children.contains(where: { $0.status == .failed })
            return HeistReportNode(
                path: "\(path)[\(iterationIndex)]",
                kind: kind,
                status: failed ? .failed : .passed,
                message: "iteration \(iterationIndex)",
                durationMs: iterationResults.reduce(0) { $0 + $1.durationMs },
                action: nil,
                expectation: nil,
                caseSelection: nil,
                forEachResult: nil,
                children: children
            )
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
        (expectation?.predicate == nil ? 0 : 1) + children.reduce(0) { $0 + $1.expectationsChecked }
    }

    var expectationsMet: Int {
        (expectation?.met == true && expectation?.predicate != nil ? 1 : 0) + children.reduce(0) { $0 + $1.expectationsMet }
    }

    var finalActionResultsInExecutionOrder: [ActionResult] {
        [
            action?.finalActionResult,
        ].compactMap { $0 } + children.flatMap(\.finalActionResultsInExecutionOrder)
    }

    var legacyFlatRows: [HeistReportFlatRow] {
        let row = HeistReportFlatRow(index: 0, node: self)
        switch kind {
        case .forEachElement, .forEachString:
            return [row]
        case .action, .wait, .conditional, .waitForCases, .forEachIteration, .warn, .fail:
            return [row] + children.flatMap(\.legacyFlatRows)
        }
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

    init(step: HeistStep) {
        switch step {
        case .action: self = .action
        case .wait: self = .wait
        case .conditional: self = .conditional
        case .waitForCases: self = .waitForCases
        case .forEachElement: self = .forEachElement
        case .forEachString: self = .forEachString
        case .warn: self = .warn
        case .fail: self = .fail
        }
    }

    var reportName: String {
        rawValue
    }
}

enum HeistReportStepStatus {
    case passed
    case failed
    case skipped
    case warned

    init(step: HeistStep, outcome: HeistExecutionStepResult) {
        if outcome.skipped != nil {
            self = .skipped
        } else if case .warn = step {
            self = .warned
        } else if Self.stepFailed(step: step, outcome: outcome) {
            self = .failed
        } else {
            self = .passed
        }
    }

    private static func stepFailed(
        step: HeistStep,
        outcome: HeistExecutionStepResult
    ) -> Bool {
        switch step {
        case .action:
            if outcome.actionResult?.success == false { return true }
            if outcome.expectationActionResult?.success == false { return true }
            if outcome.expectation?.met == false { return true }
            return outcome.actionResult == nil
        case .wait:
            if outcome.expectation?.met == false { return true }
            return outcome.actionResult?.success != true
        case .conditional:
            return outcome.stopsHeist && (outcome.childResults?.isEmpty ?? true)
        case .waitForCases:
            if outcome.caseSelection?.timedOut == true,
               outcome.caseSelection?.elseRan != true {
                return true
            }
            return outcome.stopsHeist && (outcome.childResults?.isEmpty ?? true)
        case .forEachElement, .forEachString:
            return outcome.forEachResult?.failureReason != nil
        case .warn:
            return false
        case .fail:
            return true
        }
    }
}

struct HeistReportFlatRow {
    let index: Int
    let node: HeistReportNode

    var commandName: String {
        node.action?.commandName ?? node.kind.reportName
    }

    var fenceCommand: TheFence.Command? {
        node.action?.fenceCommand
    }

    var target: ElementTarget? {
        node.action?.target
    }

    var finalActionResult: ActionResult? {
        node.action?.finalActionResult
    }

    var response: FenceResponse? {
        if let action = node.action,
           let result = action.finalActionResult {
            return .action(command: action.fenceCommand, result: result, expectation: node.expectation)
        }
        if let failureMessage {
            return .error(failureMessage)
        }
        return nil
    }

    var failureMessage: String? {
        switch node.status {
        case .passed, .warned:
            return nil
        case .skipped, .failed:
            break
        }
        if let message = node.message {
            return message
        }
        if let result = finalActionResult, !result.success {
            return result.message ?? "action failed"
        }
        if node.expectation?.met == false {
            return node.expectation?.actual ?? "expectation not met"
        }
        if node.kind == .waitForCases,
           node.caseSelection?.timedOut == true,
           node.caseSelection?.elseRan != true {
            return "wait_for_cases timed out"
        }
        if let reason = node.forEachResult?.failureReason {
            return reason
        }
        return "heist step failed"
    }

    var playbackFailure: PlaybackFailure? {
        let failedStep: PlaybackFailure.FailedStep
        if let fenceCommand {
            failedStep = PlaybackFailure.FailedStep(command: fenceCommand, target: target)
        } else {
            failedStep = PlaybackFailure.FailedStep(commandName: commandName, target: target)
        }
        if let result = finalActionResult,
           result.success == false || node.expectation?.met == false {
            return .actionFailed(
                step: failedStep,
                result: result,
                expectation: node.expectation,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        guard let response,
              case .error(let message, _) = response
        else { return nil }
        return .fenceError(
            step: failedStep,
            message: message,
            interface: nil,
            diagnosticCaptureFailure: nil
        )
    }

    func indexed(_ index: Int) -> Self {
        HeistReportFlatRow(index: index, node: node)
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
