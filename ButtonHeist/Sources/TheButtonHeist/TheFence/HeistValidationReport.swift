import ThePlans

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

public enum HeistValidationState: String, Sendable, Equatable {
    case valid
    case invalid
    case notEvaluated = "not_evaluated"
}

public enum HeistLintState: String, Sendable, Equatable {
    case passed
    case findings
    case notEvaluated = "not_evaluated"
}

public struct HeistPlanSummary: Sendable, Equatable {
    public let version: Int
    public let name: String?
    public let parameter: HeistParameter
    public let definitionCount: Int
    public let topLevelStepCount: Int

    init(_ plan: HeistPlan) {
        version = plan.version
        name = plan.name
        parameter = plan.parameter
        definitionCount = plan.definitions.count
        topLevelStepCount = plan.body.count
    }
}

public enum HeistPlanValidation: Sendable, Equatable {
    case valid(HeistPlanSummary)
    case invalid([HeistBuildDiagnostic])

    public var isValid: Bool {
        if case .valid = self { true } else { false }
    }

    public var diagnostics: [HeistBuildDiagnostic] {
        if case .invalid(let diagnostics) = self { diagnostics } else { [] }
    }
}

public struct HeistInvocationValidation: Sendable, Equatable {
    public let state: HeistValidationState
    public let argumentProvided: Bool
    public let diagnostics: [HeistBuildDiagnostic]

    init(
        state: HeistValidationState,
        argumentProvided: Bool,
        diagnostics: [HeistBuildDiagnostic] = []
    ) {
        self.state = state
        self.argumentProvided = argumentProvided
        self.diagnostics = diagnostics
    }
}

public struct HeistLintReport: Sendable, Equatable {
    public let mode: HeistValidationLintMode
    public let state: HeistLintState
    public let findings: [HeistPlanLintFinding]

    public var hasErrors: Bool {
        findings.contains { $0.severity == .error }
    }

    init(
        mode: HeistValidationLintMode,
        state: HeistLintState,
        findings: [HeistPlanLintFinding] = []
    ) {
        self.mode = mode
        self.state = state
        self.findings = findings
    }
}

public struct HeistValidationReport: Sendable, Equatable {
    public let plan: HeistPlanValidation
    public let invocation: HeistInvocationValidation
    public let lint: HeistLintReport
    public let canonicalPlan: String?

    public var admissible: Bool {
        plan.isValid && invocation.state == .valid
    }

    public var commandPassed: Bool {
        admissible && !lint.hasErrors
    }

    init(
        plan: HeistPlanValidation,
        invocation: HeistInvocationValidation,
        lint: HeistLintReport,
        canonicalPlan: String?
    ) {
        self.plan = plan
        self.invocation = invocation
        self.lint = lint
        self.canonicalPlan = canonicalPlan
    }

    static func rejectedPlan(
        diagnostics: [HeistBuildDiagnostic],
        argumentProvided: Bool,
        lintMode: HeistValidationLintMode
    ) -> Self {
        Self(
            plan: .invalid(diagnostics),
            invocation: HeistInvocationValidation(
                state: .notEvaluated,
                argumentProvided: argumentProvided
            ),
            lint: HeistLintReport(mode: lintMode, state: .notEvaluated),
            canonicalPlan: nil
        )
    }
}
