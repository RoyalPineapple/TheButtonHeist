public extension Double {
    static func seconds(_ value: Double) -> Double {
        value
    }

    static func milliseconds(_ value: Double) -> Double {
        value / 1_000
    }
}

public struct WaitFor: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlan]
    public let heistBuildDiagnostics: [String]

    public init(
        _ predicate: AccessibilityPredicateExpr,
        timeout: Double = 0
    ) {
        heistSteps = [.wait(WaitStep(predicate: predicate, timeout: timeout))]
        heistDefinitions = []
        heistBuildDiagnostics = []
    }

    @_disfavoredOverload
    public init(
        _ predicate: AccessibilityPredicate,
        timeout: Double = 0
    ) {
        self.init(.predicate(predicate), timeout: timeout)
    }

    public init(
        timeout: Double,
        @PredicateBranchBuilder _ branches: () -> PredicateBranches
    ) {
        let branchSet = branches()
        heistSteps = [.waitForCases(makeWaitForCasesStep(
            timeout: timeout,
            cases: branchSet.cases,
            elseBody: branchSet.elseBody
        ))]
        heistDefinitions = branchSet.definitions
        heistBuildDiagnostics = branchSet.diagnostics
    }
}

public struct If: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlan]
    public let heistBuildDiagnostics: [String]

    public init(
        @PredicateBranchBuilder _ branches: () -> PredicateBranches
    ) {
        let branchSet = branches()
        heistSteps = [.conditional(makeConditionalStep(
            cases: branchSet.cases,
            elseBody: branchSet.elseBody
        ))]
        heistDefinitions = branchSet.definitions
        heistBuildDiagnostics = branchSet.diagnostics
    }
}

public struct Case {
    let predicateBranch: PredicateBranch

    public init(
        _ predicate: AccessibilityPredicateExpr,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        let content = content()
        predicateBranch = .case(
            PredicateCase(predicate: predicate, body: content.heistSteps),
            definitions: content.heistDefinitions,
            diagnostics: content.heistBuildDiagnostics
        )
    }

    @_disfavoredOverload
    public init(
        _ predicate: AccessibilityPredicate,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        self.init(.predicate(predicate), content)
    }
}

public struct Else {
    let predicateBranch: PredicateBranch

    public init(
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        let content = content()
        predicateBranch = .else(
            content.heistSteps,
            definitions: content.heistDefinitions,
            diagnostics: content.heistBuildDiagnostics
        )
    }
}

public struct Warn: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlan] = []

    public init(_ message: String) {
        heistSteps = [.warn(WarnStep(message: message))]
    }
}

public struct Fail: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlan] = []

    public init(_ message: String) {
        heistSteps = [.fail(FailStep(message: message))]
    }
}

public enum PredicateBranch {
    case `case`(PredicateCase, definitions: [HeistPlan], diagnostics: [String])
    case `else`([HeistStep], definitions: [HeistPlan], diagnostics: [String])
}

public struct PredicateBranches {
    public let cases: [PredicateCase]
    public let elseBody: [HeistStep]?
    public let definitions: [HeistPlan]
    public let diagnostics: [String]
}

@resultBuilder
public enum PredicateBranchBuilder {
    public static func buildExpression(_ expression: Case) -> [PredicateBranch] {
        [expression.predicateBranch]
    }

    public static func buildExpression(_ expression: Else) -> [PredicateBranch] {
        [expression.predicateBranch]
    }

    public static func buildBlock(_ components: [PredicateBranch]...) -> [PredicateBranch] {
        components.flatMap { $0 }
    }

    public static func buildFinalResult(_ branches: [PredicateBranch]) -> PredicateBranches {
        var cases: [PredicateCase] = []
        var elseBody: [HeistStep]?
        var definitions: [HeistPlan] = []
        var diagnostics: [String] = []
        for branch in branches {
            switch branch {
            case .case(let predicateCase, let branchDefinitions, let branchDiagnostics):
                precondition(elseBody == nil, "Case must appear before Else in a heist branch block")
                cases.append(predicateCase)
                definitions.append(contentsOf: branchDefinitions)
                diagnostics.append(contentsOf: branchDiagnostics)
            case .else(let steps, let branchDefinitions, let branchDiagnostics):
                precondition(elseBody == nil, "A heist branch block accepts at most one Else")
                elseBody = steps
                definitions.append(contentsOf: branchDefinitions)
                diagnostics.append(contentsOf: branchDiagnostics)
            }
        }
        return PredicateBranches(cases: cases, elseBody: elseBody, definitions: definitions, diagnostics: diagnostics)
    }
}

private func makeConditionalStep(
    cases: [PredicateCase],
    elseBody: [HeistStep]? = nil
) -> ConditionalStep {
    do {
        return try ConditionalStep(cases: cases, elseBody: elseBody)
    } catch {
        preconditionFailure("ButtonHeistDSL requires at least one If Case")
    }
}

private func makeWaitForCasesStep(
    timeout: Double,
    cases: [PredicateCase],
    elseBody: [HeistStep]? = nil
) -> WaitForCasesStep {
    do {
        return try WaitForCasesStep(timeout: timeout, cases: cases, elseBody: elseBody)
    } catch HeistPlanError.negativeTimeout {
        preconditionFailure("ButtonHeistDSL WaitFor timeout must be non-negative")
    } catch {
        preconditionFailure("ButtonHeistDSL WaitFor case block requires at least one Case")
    }
}
