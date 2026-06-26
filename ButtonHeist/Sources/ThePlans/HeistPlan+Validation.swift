import Foundation

// AuthoringLint owns quality guidance for durable authored tests. Findings do
// not decide whether a plan can execute; RuntimeSafety is enforced separately
// when `HeistPlan` values are created.
public enum HeistPlanLintMode: Sendable, Equatable {
    case compositionQuality
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
        var linter = HeistPlanLinter(mode: mode)
        let traversal = HeistPlanTraversal()
        traversal.walk(self, visitor: &linter)
        return linter.findings
    }
}

private struct HeistPlanLinter: HeistPlanTraversalVisitor {
    let mode: HeistPlanLintMode

    var findings: [HeistPlanLintFinding] = []

    mutating func visitStep(_ step: HeistStep, context: HeistTraversalContext) {
        if isViewportSetup(step), context.nextStep?.isSemanticActionStep == true {
            findings.append(viewportBeforeSemanticActionFinding(path: context.path))
        }
    }

    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext) {
        switch action.command.authoringLintKind {
        case .semantic:
            if action.expectation == nil, action.expectationWaiver == nil, mode.requiresExpectationFinding {
                findings.append(missingExpectationFinding(path: context.path))
            }
        case .typeTextWithoutTarget:
            if mode.requiresExpectationFinding {
                findings.append(typeTextTargetFinding(path: context.path))
            }
        case .mechanical:
            if mode == .strictTest {
                findings.append(mechanicalFinding(path: context.path))
            }
        case .viewport:
            if mode == .strictTest {
                findings.append(viewportFinding(path: context.path))
            }
        case .ambient:
            if action.expectation == nil, action.expectationWaiver == nil, mode.requiresExpectationFinding {
                findings.append(ambientExpectationFinding(path: context.path))
            }
        case .observation:
            break
        }
    }

    mutating func visitPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext) {
        if predicateCase.body.isEmpty {
            findings.append(emptyBranchFinding(path: context.path))
        }
    }

    mutating func visitElseBody(_ body: [HeistStep], context: HeistTraversalContext) {
        if body.isEmpty {
            findings.append(emptyBranchFinding(path: context.path))
        }
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
            message: "Pre-action viewport movement immediately precedes a semantic action",
            suggestion: "Remove the viewport movement; semantic actions own reveal and element inflation"
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
        return action.command.authoringLintKind == .viewport
    }

}

private enum HeistCommandAuthoringLintKind: Equatable {
    case semantic
    case typeTextWithoutTarget
    case mechanical
    case viewport
    case ambient
    case observation
}

private extension HeistActionCommand {
    var authoringLintKind: HeistCommandAuthoringLintKind {
        switch self {
        case .activate, .increment, .decrement, .customAction, .rotor:
            return .semantic
        case .typeText(_, let target, _):
            return target == nil ? .typeTextWithoutTarget : .semantic
        case .mechanicalTap, .mechanicalLongPress, .mechanicalSwipe, .mechanicalDrag:
            return .mechanical
        case .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge:
            return .viewport
        case .editAction, .setPasteboard, .dismissKeyboard:
            return .ambient
        case .takeScreenshot:
            return .observation
        }
    }
}

private extension HeistStep {
    var isSemanticActionStep: Bool {
        guard case .action(let action) = self else { return false }
        return action.command.authoringLintKind == .semantic
    }
}

private extension HeistPlanLintMode {
    var requiresExpectationFinding: Bool {
        switch self {
        case .compositionQuality, .strictTest:
            return true
        }
    }
}
