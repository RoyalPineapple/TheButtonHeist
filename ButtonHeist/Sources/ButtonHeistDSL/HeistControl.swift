import TheScore

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

    public init(
        _ predicate: AccessibilityPredicate,
        timeout: Double = 0
    ) {
        heistSteps = [.wait(WaitStep(predicate: predicate, timeout: timeout))]
    }

    public init(
        timeout: Double,
        @PredicateBranchBuilder _ branches: () -> PredicateBranches
    ) {
        let branchSet = branches()
        heistSteps = [.waitForCases(makeWaitForCasesStep(
            timeout: timeout,
            cases: branchSet.cases,
            elseSteps: branchSet.elseSteps
        ))]
    }
}

public struct If: HeistContent {
    public let heistSteps: [HeistStep]

    public init(
        _ predicate: AccessibilityPredicate,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        heistSteps = [.conditional(makeConditionalStep(
            cases: [PredicateCase(predicate: predicate, steps: content().heistSteps)]
        ))]
    }

    public init(
        _ predicate: AccessibilityPredicate,
        @HeistBuilder _ content: () -> some HeistContent,
        @HeistBuilder otherwise: () -> some HeistContent
    ) {
        heistSteps = [.conditional(makeConditionalStep(
            cases: [PredicateCase(predicate: predicate, steps: content().heistSteps)],
            elseSteps: otherwise().heistSteps
        ))]
    }

    public init(
        @PredicateBranchBuilder _ branches: () -> PredicateBranches
    ) {
        let branchSet = branches()
        heistSteps = [.conditional(makeConditionalStep(
            cases: branchSet.cases,
            elseSteps: branchSet.elseSteps
        ))]
    }
}

public struct Case {
    let predicateBranch: PredicateBranch

    public init(
        _ predicate: AccessibilityPredicate,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        predicateBranch = .case(PredicateCase(predicate: predicate, steps: content().heistSteps))
    }
}

public struct Else {
    let predicateBranch: PredicateBranch

    public init(
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        predicateBranch = .else(content().heistSteps)
    }
}

public struct Warn: HeistContent {
    public let heistSteps: [HeistStep]

    public init(_ message: String) {
        heistSteps = [.warn(WarnStep(message: message))]
    }
}

public struct Fail: HeistContent {
    public let heistSteps: [HeistStep]

    public init(_ message: String) {
        heistSteps = [.fail(FailStep(message: message))]
    }
}

public enum PredicateBranch {
    case `case`(PredicateCase)
    case `else`([HeistStep])
}

public struct PredicateBranches {
    public let cases: [PredicateCase]
    public let elseSteps: [HeistStep]?
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

    public static func buildArray(_ components: [[PredicateBranch]]) -> [PredicateBranch] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [PredicateBranch]?) -> [PredicateBranch] {
        component ?? []
    }

    public static func buildEither(first component: [PredicateBranch]) -> [PredicateBranch] {
        component
    }

    public static func buildEither(second component: [PredicateBranch]) -> [PredicateBranch] {
        component
    }

    public static func buildFinalResult(_ branches: [PredicateBranch]) -> PredicateBranches {
        var cases: [PredicateCase] = []
        var elseSteps: [HeistStep]?
        for branch in branches {
            switch branch {
            case .case(let predicateCase):
                precondition(elseSteps == nil, "Case must appear before Else in a heist branch block")
                cases.append(predicateCase)
            case .else(let steps):
                precondition(elseSteps == nil, "A heist branch block accepts at most one Else")
                elseSteps = steps
            }
        }
        return PredicateBranches(cases: cases, elseSteps: elseSteps)
    }
}

private func makeConditionalStep(
    cases: [PredicateCase],
    elseSteps: [HeistStep]? = nil
) -> ConditionalStep {
    do {
        return try ConditionalStep(cases: cases, elseSteps: elseSteps)
    } catch {
        preconditionFailure("ButtonHeistDSL requires at least one If Case")
    }
}

private func makeWaitForCasesStep(
    timeout: Double,
    cases: [PredicateCase],
    elseSteps: [HeistStep]? = nil
) -> WaitForCasesStep {
    do {
        return try WaitForCasesStep(timeout: timeout, cases: cases, elseSteps: elseSteps)
    } catch HeistPlanError.negativeTimeout {
        preconditionFailure("ButtonHeistDSL WaitFor timeout must be non-negative")
    } catch {
        preconditionFailure("ButtonHeistDSL WaitFor case block requires at least one Case")
    }
}
