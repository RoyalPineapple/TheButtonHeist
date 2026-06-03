import Foundation

public enum HeistPlanLintMode: Sendable, Equatable {
    case recordingQuality
    case strictTest
}

public struct HeistPlanLintFinding: Sendable, Equatable {
    public enum Severity: String, Sendable, Equatable {
        case warning
        case error
    }

    public let severity: Severity
    public let path: String
    public let message: String
    public let suggestion: String?

    public init(
        severity: Severity,
        path: String,
        message: String,
        suggestion: String? = nil
    ) {
        self.severity = severity
        self.path = path
        self.message = message
        self.suggestion = suggestion
    }
}

public extension HeistPlan {
    func lint(_ mode: HeistPlanLintMode) -> [HeistPlanLintFinding] {
        HeistPlanLinter(mode: mode).lint(steps: steps, path: "$.steps")
    }
}

private struct HeistPlanLinter {
    let mode: HeistPlanLintMode

    func lint(steps: [HeistStep], path: String) -> [HeistPlanLintFinding] {
        var findings: [HeistPlanLintFinding] = []
        for (index, step) in steps.enumerated() {
            findings += lint(step: step, path: "\(path)[\(index)]")
            if isViewportSetup(step), let next = steps[safe: index + 1], next.isSemanticActionStep {
                findings.append(viewportBeforeSemanticActionFinding(path: "\(path)[\(index)]"))
            }
        }
        return findings
    }

    private func lint(step: HeistStep, path: String) -> [HeistPlanLintFinding] {
        switch step {
        case .action(let step):
            return lint(action: step, path: "\(path).action")
        case .wait:
            return []
        case .conditional(let step):
            return lint(cases: step.cases, elseSteps: step.elseSteps, path: "\(path).conditional")
        case .waitForCases(let step):
            return lint(cases: step.cases, elseSteps: step.elseSteps, path: "\(path).wait_for_cases")
        case .forEachElement(let step):
            return lint(forEachElement: step, path: "\(path).for_each_element")
        case .forEachString(let step):
            return lint(forEachString: step, path: "\(path).for_each_string")
        case .warn, .fail:
            return []
        }
    }

    private func lint(action: ActionStep, path: String) -> [HeistPlanLintFinding] {
        var findings: [HeistPlanLintFinding] = []
        switch action.command.validationKind {
        case .semantic:
            if action.expectation == nil, action.expectationWaiver == nil, mode.requiresExpectationFinding {
                findings.append(missingExpectationFinding(path: path))
            }
        case .typeTextWithoutTarget:
            if mode.requiresExpectationFinding {
                findings.append(typeTextTargetFinding(path: path))
            }
        case .mechanical:
            if mode == .strictTest {
                findings.append(mechanicalFinding(path: path))
            }
        case .viewport:
            if mode == .strictTest {
                findings.append(viewportFinding(path: path))
            }
        case .ambient:
            if action.expectation == nil, action.expectationWaiver == nil, mode.requiresExpectationFinding {
                findings.append(ambientExpectationFinding(path: path))
            }
        }
        return findings
    }

    private func lint(
        cases: [PredicateCase],
        elseSteps: [HeistStep]?,
        path: String
    ) -> [HeistPlanLintFinding] {
        var findings: [HeistPlanLintFinding] = []
        for (index, predicateCase) in cases.enumerated() {
            let casePath = "\(path).cases[\(index)]"
            if predicateCase.steps.isEmpty {
                findings.append(emptyBranchFinding(path: casePath))
            }
            findings += lint(steps: predicateCase.steps, path: "\(casePath).steps")
        }
        if let elseSteps {
            if elseSteps.isEmpty {
                findings.append(emptyBranchFinding(path: "\(path).else_steps"))
            }
            findings += lint(steps: elseSteps, path: "\(path).else_steps")
        }
        return findings
    }

    private func lint(forEachElement step: ForEachElementStep, path: String) -> [HeistPlanLintFinding] {
        lint(steps: step.steps, path: "\(path).steps")
    }

    private func lint(forEachString step: ForEachStringStep, path: String) -> [HeistPlanLintFinding] {
        lint(steps: step.steps, path: "\(path).steps")
    }

    private func missingExpectationFinding(path: String) -> HeistPlanLintFinding {
        .init(
            severity: mode == .strictTest ? .error : .warning,
            path: path,
            message: "Semantic action has no expectation",
            suggestion: "Attach .expect(...) or .withoutExpectation(\"reason\")"
        )
    }

    private func typeTextTargetFinding(path: String) -> HeistPlanLintFinding {
        .init(
            severity: mode == .strictTest ? .error : .warning,
            path: path,
            message: "TypeText has no semantic target",
            suggestion: "Use TypeText(text, into: target) for durable semantic tests"
        )
    }

    private func mechanicalFinding(path: String) -> HeistPlanLintFinding {
        .init(
            severity: .error,
            path: path,
            message: "Mechanical command appears in strict semantic-test mode",
            suggestion: "Use semantic actions for normal UI, or keep Mechanical.* only for explicit spatial tests"
        )
    }

    private func viewportFinding(path: String) -> HeistPlanLintFinding {
        .init(
            severity: .error,
            path: path,
            message: "Viewport command appears in strict semantic-test mode",
            suggestion: "Semantic actions own reveal and viewport mechanics"
        )
    }

    private func ambientExpectationFinding(path: String) -> HeistPlanLintFinding {
        .init(
            severity: .warning,
            path: path,
            message: "Ambient action has no expectation",
            suggestion: "Attach .expect(...) or .withoutExpectation(\"reason\") when this side effect has no durable semantic outcome"
        )
    }

    private func viewportBeforeSemanticActionFinding(path: String) -> HeistPlanLintFinding {
        .init(
            severity: mode == .strictTest ? .error : .warning,
            path: path,
            message: "Viewport setup immediately precedes a semantic action",
            suggestion: "Delete viewport setup; semantic actions own reveal and actionability"
        )
    }

    private func emptyBranchFinding(path: String) -> HeistPlanLintFinding {
        .init(
            severity: .error,
            path: path,
            message: "Branch has no steps",
            suggestion: "Add a step or remove the empty branch"
        )
    }

    private func isViewportSetup(_ step: HeistStep) -> Bool {
        guard case .action(let action) = step else { return false }
        return action.command.validationKind == .viewport
    }

}

private enum HeistCommandValidationKind: Equatable {
    case semantic
    case typeTextWithoutTarget
    case mechanical
    case viewport
    case ambient
}

private extension HeistActionCommand {
    var validationKind: HeistCommandValidationKind {
        switch self {
        case .activate, .increment, .decrement, .customAction, .rotor:
            return .semantic
        case .typeText(_, let target):
            return target == nil ? .typeTextWithoutTarget : .semantic
        case .mechanicalTap, .mechanicalLongPress, .mechanicalSwipe, .mechanicalDrag:
            return .mechanical
        case .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge:
            return .viewport
        case .editAction, .setPasteboard, .dismissKeyboard:
            return .ambient
        }
    }
}

private extension HeistStep {
    var isSemanticActionStep: Bool {
        guard case .action(let action) = self else { return false }
        return action.command.validationKind == .semantic
    }
}

private extension HeistPlanLintMode {
    var requiresExpectationFinding: Bool {
        switch self {
        case .recordingQuality, .strictTest:
            return true
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
