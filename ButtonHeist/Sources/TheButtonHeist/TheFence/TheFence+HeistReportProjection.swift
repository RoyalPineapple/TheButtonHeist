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

    init(plan: HeistPlan, result: HeistExecutionResult) {
        self.nodes = Self.nodes(
            steps: plan.body,
            outcomes: result.steps,
            path: "$.body",
            definitionScope: plan
        )
        self.summary = HeistReportSummary(result: result, nodes: nodes)
    }

    var finalActionResultsInExecutionOrder: [ActionResult] {
        nodes.flatMap(\.finalActionResultsInExecutionOrder)
    }

    private static func nodes(
        steps: [HeistStep],
        outcomes: [HeistExecutionStepResult],
        path: String,
        definitionScope: HeistPlan
    ) -> [HeistReportNode] {
        outcomes.compactMap { outcome in
            guard let siblingIndex = outcome.path.stepIndex(in: path),
                  let step = steps[safe: siblingIndex] else { return nil }
            return node(
                step: step,
                outcome: outcome,
                definitionScope: definitionScope
            )
        }
    }

    private static func node(
        step: HeistStep,
        outcome: HeistExecutionStepResult,
        definitionScope: HeistPlan
    ) -> HeistReportNode {
        let kind = HeistReportStepKind(step: step)
        return HeistReportNode(
            path: outcome.path,
            kind: kind,
            status: HeistReportStepStatus(step: step, outcome: outcome),
            message: outcome.skipped?.reason ?? outcome.message,
            durationMs: outcome.durationMs,
            action: actionProjection(for: step, outcome: outcome),
            expectation: outcome.expectation,
            caseSelection: outcome.caseSelection,
            forEachResult: outcome.forEachResult,
            children: children(for: step, outcome: outcome, path: outcome.path, definitionScope: definitionScope)
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
        path: String,
        definitionScope: HeistPlan
    ) -> [HeistReportNode] {
        let children = outcome.children
        guard !children.isEmpty else { return [] }
        switch step {
        case .conditional(let conditional):
            if let selectedCaseIndex = outcome.caseSelection?.selectedCaseIndex,
               let selectedCase = conditional.cases[safe: selectedCaseIndex] {
                return nodes(
                    steps: selectedCase.body,
                    outcomes: children,
                    path: "\(path).conditional.cases[\(selectedCaseIndex)].body",
                    definitionScope: definitionScope
                )
            }
            if outcome.caseSelection?.elseRan == true {
                return nodes(
                    steps: conditional.elseBody ?? [],
                    outcomes: children,
                    path: "\(path).conditional.else_body",
                    definitionScope: definitionScope
                )
            }
            return []
        case .waitForCases(let waitForCases):
            if let selectedCaseIndex = outcome.caseSelection?.selectedCaseIndex,
               let selectedCase = waitForCases.cases[safe: selectedCaseIndex] {
                return nodes(
                    steps: selectedCase.body,
                    outcomes: children,
                    path: "\(path).wait_for_cases.cases[\(selectedCaseIndex)].body",
                    definitionScope: definitionScope
                )
            }
            if outcome.caseSelection?.elseRan == true {
                return nodes(
                    steps: waitForCases.elseBody ?? [],
                    outcomes: children,
                    path: "\(path).wait_for_cases.else_body",
                    definitionScope: definitionScope
                )
            }
            return []
        case .forEachElement(let forEach):
            return iterationNodesFromRuntime(
                kind: .forEachIteration,
                bodySteps: forEach.body,
                iterationResults: children,
                path: "\(path).for_each_element.iterations",
                definitionScope: definitionScope
            )
        case .forEachString(let forEach):
            return iterationNodesFromRuntime(
                kind: .forEachIteration,
                bodySteps: forEach.body,
                iterationResults: children,
                path: "\(path).for_each_string.iterations",
                definitionScope: definitionScope
            )
        case .heist(let plan):
            return nodes(
                steps: plan.body,
                outcomes: children,
                path: "\(path).heist.body",
                definitionScope: plan
            )
        case .invoke(let invoke):
            guard let definition = definitionScope.heistDefinition(at: invoke.path) else { return [] }
            return nodes(
                steps: definition.body,
                outcomes: children,
                path: "\(path).invoke.body",
                definitionScope: definition
            )
        case .action, .wait, .warn, .fail:
            return []
        }
    }

    private static func iterationNodesFromRuntime(
        kind: HeistReportStepKind,
        bodySteps: [HeistStep],
        iterationResults: [HeistExecutionStepResult],
        path: String,
        definitionScope: HeistPlan
    ) -> [HeistReportNode] {
        guard !bodySteps.isEmpty, !iterationResults.isEmpty else { return [] }
        return iterationResults.compactMap { iterationResult in
            guard iterationResult.kind == .forEachIteration else { return nil }
            let iterationPath = iterationResult.path
            let children = nodes(
                steps: bodySteps,
                outcomes: iterationResult.children,
                path: "\(iterationPath).body",
                definitionScope: definitionScope
            )
            let failed = children.contains(where: { $0.status == .failed })
            return HeistReportNode(
                path: iterationPath,
                kind: kind,
                status: failed || iterationResult.isFailure ? .failed : .passed,
                message: iterationResult.message,
                durationMs: iterationResult.durationMs,
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

    var expectationMet: Bool? {
        guard expectation?.predicate != nil else { return nil }
        return expectation?.met
    }

    var finalActionResultsInExecutionOrder: [ActionResult] {
        [
            action?.finalActionResult,
        ].compactMap { $0 } + children.flatMap(\.finalActionResultsInExecutionOrder)
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
    case heist
    case invoke

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
        case .heist: self = .heist
        case .invoke: self = .invoke
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
            return outcome.stopsHeist && outcome.children.isEmpty
        case .waitForCases:
            if outcome.caseSelection?.timedOut == true,
               outcome.caseSelection?.elseRan != true {
                return true
            }
            return outcome.stopsHeist && outcome.children.isEmpty
        case .forEachElement, .forEachString:
            return outcome.forEachResult?.failureReason != nil
        case .heist, .invoke:
            return outcome.children.contains(where: { $0.isFailure }) || outcome.stopsHeist
        case .warn:
            return false
        case .fail:
            return true
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    func stepIndex(in bodyPath: String) -> Int? {
        guard hasPrefix(bodyPath) else { return nil }
        let bracketStart = index(startIndex, offsetBy: bodyPath.count)
        guard bracketStart < endIndex, self[bracketStart] == "[" else { return nil }
        guard let bracketEnd = self[bracketStart...].firstIndex(of: "]") else { return nil }
        guard index(after: bracketEnd) == endIndex else { return nil }
        return Int(self[index(after: bracketStart)..<bracketEnd])
    }
}
