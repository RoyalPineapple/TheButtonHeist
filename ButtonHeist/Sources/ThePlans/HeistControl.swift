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
        self.init(predicate: predicate, timeout: timeout, elseBody: nil, definitions: [], diagnostics: [])
    }

    @_disfavoredOverload
    public init(
        _ predicate: AccessibilityPredicate,
        timeout: Double = 0
    ) {
        self.init(.predicate(predicate), timeout: timeout)
    }

    public init(
        _ predicate: ElementPredicateTemplate,
        timeout: Double = 0
    ) {
        self.init(.present(predicate), timeout: timeout)
    }

    public func `else`(
        @HeistBuilder _ content: () -> some HeistContent
    ) -> WaitFor {
        guard heistSteps.count == 1,
              case .wait(let step) = heistSteps[0] else {
            preconditionFailure("ButtonHeistDSL WaitFor else requires a WaitFor(predicate, timeout:) gate")
        }
        guard step.elseBody == nil else {
            preconditionFailure("ButtonHeistDSL WaitFor accepts at most one else body")
        }
        let content = content()
        return WaitFor(
            predicate: step.predicate,
            timeout: step.timeout,
            elseBody: content.heistSteps,
            definitions: heistDefinitions + content.heistDefinitions,
            diagnostics: heistBuildDiagnostics + content.heistBuildDiagnostics
        )
    }

    private init(
        predicate: AccessibilityPredicateExpr,
        timeout: Double,
        elseBody: [HeistStep]?,
        definitions: [HeistPlan],
        diagnostics: [String]
    ) {
        heistSteps = [.wait(WaitStep(predicate: predicate, timeout: timeout, elseBody: elseBody))]
        heistDefinitions = definitions
        heistBuildDiagnostics = diagnostics
    }
}

public struct RepeatUntil: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlan]
    public let heistBuildDiagnostics: [String]

    public init(
        _ predicate: AccessibilityPredicateExpr,
        timeout: Double,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        let content = content()
        self.init(
            predicate: predicate,
            timeout: timeout,
            body: content.heistSteps,
            elseBody: nil,
            definitions: content.heistDefinitions,
            diagnostics: content.heistBuildDiagnostics
        )
    }

    @_disfavoredOverload
    public init(
        _ predicate: AccessibilityPredicate,
        timeout: Double,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        self.init(.predicate(predicate), timeout: timeout, content)
    }

    public init(
        _ predicate: ElementPredicateTemplate,
        timeout: Double,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        self.init(.present(predicate), timeout: timeout, content)
    }

    public func `else`(
        @HeistBuilder _ content: () -> some HeistContent
    ) -> RepeatUntil {
        guard heistSteps.count == 1,
              case .repeatUntil(let step) = heistSteps[0] else {
            preconditionFailure("ButtonHeistDSL RepeatUntil else requires a RepeatUntil(predicate, timeout:) loop")
        }
        guard step.elseBody == nil else {
            preconditionFailure("ButtonHeistDSL RepeatUntil accepts at most one else body")
        }
        let content = content()
        return RepeatUntil(
            predicate: step.predicate,
            timeout: step.timeout,
            body: step.body,
            elseBody: content.heistSteps,
            definitions: heistDefinitions + content.heistDefinitions,
            diagnostics: heistBuildDiagnostics + content.heistBuildDiagnostics
        )
    }

    private init(
        predicate: AccessibilityPredicateExpr,
        timeout: Double,
        body: [HeistStep],
        elseBody: [HeistStep]?,
        definitions: [HeistPlan],
        diagnostics: [String]
    ) {
        do {
            heistSteps = [.repeatUntil(try RepeatUntilStep(
                predicate: predicate,
                timeout: timeout,
                body: body,
                elseBody: elseBody
            ))]
            heistDefinitions = definitions
            heistBuildDiagnostics = diagnostics
        } catch {
            heistSteps = []
            heistDefinitions = []
            heistBuildDiagnostics = diagnostics + ["RepeatUntil loop is invalid: \(String(describing: error))"]
        }
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
        self.init(
            cases: branchSet.cases,
            elseBody: branchSet.elseBody,
            definitions: branchSet.definitions,
            diagnostics: branchSet.diagnostics
        )
    }

    public init(
        _ predicate: AccessibilityPredicateExpr,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        let content = content()
        self.init(
            cases: [PredicateCase(predicate: predicate, body: content.heistSteps)],
            elseBody: nil,
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

    public func `else`(
        @HeistBuilder _ content: () -> some HeistContent
    ) -> If {
        guard heistSteps.count == 1,
              case .conditional(let step) = heistSteps[0] else {
            preconditionFailure("ButtonHeistDSL If else requires an If(predicate) case body")
        }
        guard step.elseBody == nil else {
            preconditionFailure("ButtonHeistDSL If accepts at most one else body")
        }
        let content = content()
        return If(
            cases: step.cases,
            elseBody: content.heistSteps,
            definitions: heistDefinitions + content.heistDefinitions,
            diagnostics: heistBuildDiagnostics + content.heistBuildDiagnostics
        )
    }

    private init(
        cases: [PredicateCase],
        elseBody: [HeistStep]?,
        definitions: [HeistPlan],
        diagnostics: [String]
    ) {
        heistSteps = [.conditional(makeConditionalStep(
            cases: cases,
            elseBody: elseBody
        ))]
        heistDefinitions = definitions
        heistBuildDiagnostics = diagnostics
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
