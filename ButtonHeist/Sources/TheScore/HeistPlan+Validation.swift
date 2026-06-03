import Foundation

public enum HeistPlanValidationMode: Sendable, Equatable {
    case runtime
    case recordingQuality
    case strictTest
}

public struct HeistPlanValidationFinding: Sendable, Equatable {
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
    func validate(_ mode: HeistPlanValidationMode) -> [HeistPlanValidationFinding] {
        HeistPlanValidator(mode: mode).validate(steps: steps, path: "$.steps")
    }
}

private struct HeistPlanValidator {
    let mode: HeistPlanValidationMode

    func validate(steps: [HeistStep], path: String) -> [HeistPlanValidationFinding] {
        var findings: [HeistPlanValidationFinding] = []
        for (index, step) in steps.enumerated() {
            findings += validate(step: step, path: "\(path)[\(index)]")
            if isViewportSetup(step), let next = steps[safe: index + 1], next.isSemanticActionStep {
                findings.append(viewportBeforeSemanticActionFinding(path: "\(path)[\(index)]"))
            }
        }
        return findings
    }

    private func validate(step: HeistStep, path: String) -> [HeistPlanValidationFinding] {
        switch step {
        case .action(let step):
            return validate(action: step, path: "\(path).action")
        case .wait:
            return []
        case .conditional(let step):
            return validate(cases: step.cases, elseSteps: step.elseSteps, path: "\(path).conditional")
        case .waitForCases(let step):
            return validate(cases: step.cases, elseSteps: step.elseSteps, path: "\(path).wait_for_cases")
        case .forEach(let step):
            return validate(forEach: step, path: "\(path).for_each")
        case .warn, .fail:
            return []
        }
    }

    private func validate(action: ActionStep, path: String) -> [HeistPlanValidationFinding] {
        var findings: [HeistPlanValidationFinding] = []
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
        case .escapeHatch:
            if mode == .strictTest {
                findings.append(escapeHatchFinding(path: path))
            }
        }
        return findings
    }

    private func validate(
        cases: [PredicateCase],
        elseSteps: [HeistStep]?,
        path: String
    ) -> [HeistPlanValidationFinding] {
        var findings: [HeistPlanValidationFinding] = []
        for (index, predicateCase) in cases.enumerated() {
            let casePath = "\(path).cases[\(index)]"
            if predicateCase.steps.isEmpty {
                findings.append(emptyBranchFinding(path: casePath))
            }
            findings += validate(steps: predicateCase.steps, path: "\(casePath).steps")
        }
        if let elseSteps {
            if elseSteps.isEmpty {
                findings.append(emptyBranchFinding(path: "\(path).else_steps"))
            }
            findings += validate(steps: elseSteps, path: "\(path).else_steps")
        }
        return findings
    }

    private func validate(forEach step: ForEachStep, path: String) -> [HeistPlanValidationFinding] {
        var findings = validate(steps: step.steps, path: "\(path).steps")
        if step.limit > 100 {
            findings.append(.init(
                severity: mode == .runtime ? .warning : .error,
                path: "\(path).limit",
                message: "ForEach limit is too large for a durable semantic heist",
                suggestion: "Use a bounded limit of 100 or less"
            ))
        }
        return findings
    }

    private func missingExpectationFinding(path: String) -> HeistPlanValidationFinding {
        .init(
            severity: mode == .strictTest ? .error : .warning,
            path: path,
            message: "Semantic action has no expectation",
            suggestion: "Attach .expect(...) or .withoutExpectation(\"reason\")"
        )
    }

    private func typeTextTargetFinding(path: String) -> HeistPlanValidationFinding {
        .init(
            severity: mode == .strictTest ? .error : .warning,
            path: path,
            message: "TypeText has no semantic target",
            suggestion: "Use TypeText(text, into: target) for durable semantic tests"
        )
    }

    private func mechanicalFinding(path: String) -> HeistPlanValidationFinding {
        .init(
            severity: .error,
            path: path,
            message: "Mechanical command appears in strict semantic-test mode",
            suggestion: "Use semantic actions for normal UI, or keep Mechanical.* only for explicit spatial tests"
        )
    }

    private func viewportFinding(path: String) -> HeistPlanValidationFinding {
        .init(
            severity: .error,
            path: path,
            message: "Viewport command appears in strict semantic-test mode",
            suggestion: "Semantic actions own reveal and viewport mechanics"
        )
    }

    private func escapeHatchFinding(path: String) -> HeistPlanValidationFinding {
        .init(
            severity: .error,
            path: path,
            message: "Mechanical escape hatch appears in strict semantic-test mode",
            suggestion: "Use semantic actions and expectations unless this heist explicitly tests mechanics"
        )
    }

    private func viewportBeforeSemanticActionFinding(path: String) -> HeistPlanValidationFinding {
        .init(
            severity: mode == .strictTest ? .error : .warning,
            path: path,
            message: "Viewport setup immediately precedes a semantic action",
            suggestion: "Delete viewport setup; semantic actions own reveal and actionability"
        )
    }

    private func emptyBranchFinding(path: String) -> HeistPlanValidationFinding {
        .init(
            severity: mode == .runtime ? .warning : .error,
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
    case escapeHatch
}

private extension ClientMessage {
    var validationKind: HeistCommandValidationKind {
        switch self {
        case .activate, .increment, .decrement, .performCustomAction, .rotor:
            return .semantic
        case .typeText(let target):
            return target.elementTarget == nil ? .typeTextWithoutTarget : .semantic
        case .oneFingerTap, .longPress, .swipe, .drag:
            return .mechanical
        case .scroll, .scrollToVisible, .scrollToEdge:
            return .viewport
        case .editAction, .setPasteboard, .resignFirstResponder:
            return .escapeHatch
        case .clientHello, .authenticate, .requestInterface, .ping, .status, .getPasteboard, .requestScreen,
             .wait, .heistPlan:
            return .escapeHatch
        }
    }
}

private extension HeistStep {
    var isSemanticActionStep: Bool {
        guard case .action(let action) = self else { return false }
        return action.command.validationKind == .semantic
    }
}

private extension HeistPlanValidationMode {
    var requiresExpectationFinding: Bool {
        switch self {
        case .runtime:
            return false
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
