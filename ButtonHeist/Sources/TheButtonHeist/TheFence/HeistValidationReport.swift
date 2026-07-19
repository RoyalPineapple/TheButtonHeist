import ThePlans

public enum HeistValidation {
    package enum Result<Value: Sendable & Equatable>: Sendable, Equatable {
        case valid(Value)
        case invalid([HeistBuildDiagnostic])

        package var isValid: Bool { if case .valid = self { true } else { false } }

        package var diagnostics: [HeistBuildDiagnostic] {
            if case .invalid(let diagnostics) = self { diagnostics } else { [] }
        }
    }

    package enum Evaluation<Value: Sendable & Equatable>: Sendable, Equatable {
        case evaluated(Result<Value>)
        case notEvaluated

        package var isValid: Bool {
            guard case .evaluated(let result) = self else { return false }
            return result.isValid
        }

        package var diagnostics: [HeistBuildDiagnostic] {
            guard case .evaluated(let result) = self else { return [] }
            return result.diagnostics
        }
    }

    package struct PlanSummary: Sendable, Equatable {
        package let version: Int
        package let name: HeistPlanName?
        package let parameter: HeistParameter
        package let definitionCount: Int
        package let topLevelStepCount: Int

        package init(_ plan: HeistPlan) {
            version = plan.version
            name = plan.name
            parameter = plan.parameter
            definitionCount = plan.definitions.count
            topLevelStepCount = plan.body.count
        }
    }

    package struct InvocationSummary: Sendable, Equatable {
        package let argumentProvided: Bool
    }

    package enum Lint: Sendable, Equatable {
        case notEvaluated(mode: HeistValidationLintMode)
        case passed(mode: HeistValidationLintMode)
        case findings(mode: HeistValidationLintMode, values: [HeistPlanLintFinding])

        package var mode: HeistValidationLintMode {
            switch self {
            case .notEvaluated(let mode), .passed(let mode), .findings(let mode, _): mode
            }
        }

        package var findings: [HeistPlanLintFinding] {
            if case .findings(_, let findings) = self { findings } else { [] }
        }

        package var hasErrors: Bool { findings.contains { $0.severity == .error } }
    }

    public struct Report: Sendable, Equatable {
        package let plan: Result<PlanSummary>
        package let invocation: Evaluation<InvocationSummary>
        package let argumentProvided: Bool
        package let lint: Lint
        package let canonicalPlan: String?

        package var admissible: Bool { plan.isValid && invocation.isValid }

        package var commandPassed: Bool { admissible && !lint.hasErrors }

        private init(
            plan: Result<PlanSummary>,
            invocation: Evaluation<InvocationSummary>,
            argumentProvided: Bool,
            lint: Lint,
            canonicalPlan: String?
        ) {
            self.plan = plan
            self.invocation = invocation
            self.argumentProvided = argumentProvided
            self.lint = lint
            self.canonicalPlan = canonicalPlan
        }

        package static func evaluatedPlan(
            _ plan: PlanSummary,
            invocation: Result<InvocationSummary>,
            argumentProvided: Bool,
            lint: Lint,
            canonicalPlan: String
        ) -> Self {
            Self(
                plan: .valid(plan),
                invocation: .evaluated(invocation),
                argumentProvided: argumentProvided,
                lint: lint,
                canonicalPlan: canonicalPlan
            )
        }

        package static func rejectedPlan(
            diagnostics: [HeistBuildDiagnostic],
            argumentProvided: Bool,
            lintMode: HeistValidationLintMode
        ) -> Self {
            Self(
                plan: .invalid(diagnostics),
                invocation: .notEvaluated,
                argumentProvided: argumentProvided,
                lint: .notEvaluated(mode: lintMode),
                canonicalPlan: nil
            )
        }
    }
}

public enum HeistValidationLintMode: String, CaseIterable, Sendable, Equatable {
    case none
    case compositionQuality = "composition_quality"
    case strictTest = "strict_test"

    var planLintMode: HeistPlanLintMode? {
        switch self {
        case .none: nil
        case .compositionQuality: .compositionQuality
        case .strictTest: .strictTest
        }
    }
}
