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
    public let path: HeistPlanPath
    public let message: String
    public let suggestion: String?

    public init(
        severity: Severity,
        path: HeistPlanPath,
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
        HeistPlanTraversal().walkLintObservations(self) { observation in
            linter.observe(observation)
        }
        return linter.findings
    }
}

private struct HeistPlanLinter {
    let mode: HeistPlanLintMode

    var findings: [HeistPlanLintFinding] = []

    mutating func observe(_ observation: HeistPlanTraversal.LintObservation) {
        switch observation {
        case .step(let step, let context):
            inspectStep(step, context: context)
        case .action(let action, let context):
            inspectAction(action, context: context)
        case .predicateCase(let predicateCase, let context):
            inspectPredicateCase(predicateCase, context: context)
        case .elseBody(let body, let context):
            inspectElseBody(body, context: context)
        }
    }

    private mutating func inspectStep(_ step: HeistStep, context: HeistTraversalContext) {
        if step.isScrollSetup, context.nextStep?.isSemanticActionStep == true {
            findings.append(scrollBeforeSemanticActionFinding(path: context.path))
        }
    }

    private mutating func inspectAction(_ action: ActionStep, context: HeistTraversalContext) {
        switch action.command.authoringLintKind {
        case .semantic:
            if action.expectationPolicy.requiresAuthoredExpectation, mode.requiresExpectationFinding {
                findings.append(missingExpectationFinding(path: context.path))
            }
        case .typeTextWithoutTarget:
            if mode.requiresExpectationFinding {
                findings.append(typeTextTargetFinding(path: context.path))
            }
        case .spatialGesture:
            if mode == .strictTest {
                findings.append(spatialGestureFinding(path: context.path))
            }
        case .scroll:
            if mode == .strictTest {
                findings.append(scrollFinding(path: context.path))
            }
        case .ambient:
            if action.expectationPolicy.requiresAuthoredExpectation, mode.requiresExpectationFinding {
                findings.append(ambientExpectationFinding(path: context.path))
            }
        case .observation:
            break
        }
    }

    private mutating func inspectPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext) {
        if predicateCase.body.isEmpty {
            findings.append(emptyBranchFinding(path: context.path))
        }
    }

    private mutating func inspectElseBody(_ body: [HeistStep], context: HeistTraversalContext) {
        if body.isEmpty {
            findings.append(emptyBranchFinding(path: context.path))
        }
    }

    private func missingExpectationFinding(path: HeistPlanPath) -> HeistPlanLintFinding {
        .init(
            severity: mode == .strictTest ? .error : .warning,
            path: path,
            message: "Semantic action has no expectation",
            suggestion: "Attach .expect(...) or .withoutExpectation(\"reason\")"
        )
    }

    private func typeTextTargetFinding(path: HeistPlanPath) -> HeistPlanLintFinding {
        .init(
            severity: mode == .strictTest ? .error : .warning,
            path: path,
            message: "TypeText has no semantic target",
            suggestion: "Use TypeText(text, into: target) for durable semantic tests"
        )
    }

    private func spatialGestureFinding(path: HeistPlanPath) -> HeistPlanLintFinding {
        .init(
            severity: .error,
            path: path,
            message: "Spatial gesture command appears in strict semantic-test mode",
            suggestion: "Use semantic actions for normal UI, or keep gesture commands only for explicit spatial tests"
        )
    }

    private func scrollFinding(path: HeistPlanPath) -> HeistPlanLintFinding {
        .init(
            severity: .error,
            path: path,
            message: "Scroll command appears in strict semantic-test mode",
            suggestion: "Semantic actions own reveal and scrolling"
        )
    }

    private func ambientExpectationFinding(path: HeistPlanPath) -> HeistPlanLintFinding {
        .init(
            severity: .warning,
            path: path,
            message: "Ambient action has no expectation",
            suggestion: "Attach .expect(...) or .withoutExpectation(\"reason\") when this side effect has no durable semantic outcome"
        )
    }

    private func scrollBeforeSemanticActionFinding(path: HeistPlanPath) -> HeistPlanLintFinding {
        .init(
            severity: mode == .strictTest ? .error : .warning,
            path: path,
            message: "Pre-action scroll immediately precedes a semantic action",
            suggestion: "Remove the scroll; semantic actions own reveal and element inflation"
        )
    }

    private func emptyBranchFinding(path: HeistPlanPath) -> HeistPlanLintFinding {
        .init(
            severity: .error,
            path: path,
            message: "Branch has no steps",
            suggestion: "Add a step or remove the empty branch"
        )
    }

}

private enum HeistCommandAuthoringLintKind: Equatable {
    case semantic
    case typeTextWithoutTarget
    case spatialGesture
    case scroll
    case ambient
    case observation
}

private extension HeistActionCommand {
    var authoringLintKind: HeistCommandAuthoringLintKind {
        switch self {
        case .activate, .increment, .decrement, .customAction, .rotor:
            return .semantic
        case .typeText(let payload):
            return payload.target == nil ? .typeTextWithoutTarget : .semantic
        case .oneFingerTap, .longPress, .swipe, .drag:
            return .spatialGesture
        case .scroll, .scrollToVisible, .scrollToEdge:
            return .scroll
        case .dismiss, .magicTap, .editAction, .setPasteboard, .dismissKeyboard:
            return .ambient
        case .takeScreenshot:
            return .observation
        }
    }
}

private extension HeistStep {
    var isScrollSetup: Bool {
        guard case .action(let action) = self else { return false }
        return action.command.authoringLintKind == .scroll
    }

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
