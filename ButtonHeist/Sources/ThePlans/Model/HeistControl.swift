public struct WaitFor {
    private let step: WaitStep
    var heistContent: HeistContent { HeistContent([.wait(step)]) }

    public init(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout = defaultWaitTimeout
    ) {
        let step = WaitStep(predicate: predicate, timeout: timeout)
        self.step = step
    }

    public func `else`(
        @HeistBuilder _ content: () -> HeistContent
    ) -> HeistContent {
        let content = content()
        return HeistContent(
            [.wait(WaitStep(
                predicate: step.predicate,
                timeout: step.timeout,
                elseBody: content.steps
            ))],
            definitions: content.definitions,
            diagnostics: content.diagnostics
        )
    }
}

public struct RepeatUntil {
    let heistContent: HeistContent

    public init(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        @HeistBuilder _ content: () -> HeistContent
    ) {
        let content = content()
        do {
            let step = try RepeatUntilStep(
                predicate: predicate,
                timeout: timeout,
                body: content.steps
            )
            heistContent = HeistContent(
                [.repeatUntil(step)],
                definitions: content.definitions,
                diagnostics: content.diagnostics
            )
        } catch {
            heistContent = HeistContent(diagnostics: content.diagnostics + [.dslBuild(
                code: .dslInvalidRepeatUntil,
                message: "RepeatUntil loop is invalid: \(String(describing: error))"
            )])
        }
    }
}

public struct IfContent {
    let heistContent: HeistContent
    private let step: ConditionalStep

    public func `else`(
        @HeistBuilder _ content: () -> HeistContent
    ) -> HeistContent {
        let content = content()
        return HeistContent(
            [.conditional(ConditionalStep(
                completing: step,
                elseBody: content.steps
            ))],
            definitions: heistContent.definitions + content.definitions,
            diagnostics: heistContent.diagnostics + content.diagnostics
        )
    }

    fileprivate init(
        predicate: ChangeDeclaration.ScreenAssertion,
        content: HeistContent
    ) {
        let step = ConditionalStep(cases: NonEmptyArray(PredicateCase(
            predicate: predicate,
            body: content.steps
        )))
        self.step = step
        heistContent = HeistContent(
            [.conditional(step)],
            definitions: content.definitions,
            diagnostics: content.diagnostics
        )
    }
}

public func If(
    _ predicate: ChangeDeclaration.ScreenAssertion,
    @HeistBuilder _ content: () -> HeistContent
) -> IfContent {
    IfContent(predicate: predicate, content: content())
}

public func If(
    @PredicateBranchBuilder _ branches: () -> PredicateBranches
) -> HeistContent {
    let branches = branches()
    return HeistContent(
        [.conditional(ConditionalStep(cases: branches.cases, elseBody: branches.elseBody))],
        definitions: branches.definitions,
        diagnostics: branches.diagnostics
    )
}

public struct Case {
    fileprivate let predicateCase: PredicateCase
    fileprivate let definitions: [HeistPlan]
    fileprivate let diagnostics: [HeistBuildDiagnostic]

    public init(
        _ predicate: ChangeDeclaration.ScreenAssertion,
        @HeistBuilder _ content: () -> HeistContent
    ) {
        let content = content()
        predicateCase = PredicateCase(predicate: predicate, body: content.steps)
        definitions = content.definitions
        diagnostics = content.diagnostics
    }
}

public struct Else {
    fileprivate let body: [HeistStep]
    fileprivate let definitions: [HeistPlan]
    fileprivate let diagnostics: [HeistBuildDiagnostic]

    public init(
        @HeistBuilder _ content: () -> HeistContent
    ) {
        let content = content()
        body = content.steps
        definitions = content.definitions
        diagnostics = content.diagnostics
    }
}

public struct Warn {
    let heistContent: HeistContent

    public init(_ message: HeistWarningMessage) {
        heistContent = HeistContent([.warn(WarnStep(message: message))])
    }
}

public struct Fail {
    let heistContent: HeistContent

    public init(_ message: HeistFailureMessage) {
        heistContent = HeistContent([.fail(FailStep(message: message))])
    }
}

public struct PredicateCases {
    fileprivate let cases: NonEmptyArray<PredicateCase>
    fileprivate let definitions: [HeistPlan]
    fileprivate let diagnostics: [HeistBuildDiagnostic]

    fileprivate init(_ first: Case) {
        cases = NonEmptyArray(first.predicateCase)
        definitions = first.definitions
        diagnostics = first.diagnostics
    }

    fileprivate func appending(_ next: Case) -> PredicateCases {
        PredicateCases(
            cases: NonEmptyArray(cases.first, rest: cases.rest + [next.predicateCase]),
            definitions: definitions + next.definitions,
            diagnostics: diagnostics + next.diagnostics
        )
    }

    private init(
        cases: NonEmptyArray<PredicateCase>,
        definitions: [HeistPlan],
        diagnostics: [HeistBuildDiagnostic]
    ) {
        self.cases = cases
        self.definitions = definitions
        self.diagnostics = diagnostics
    }
}

public struct PredicateBranches {
    fileprivate let cases: NonEmptyArray<PredicateCase>
    fileprivate let elseBody: [HeistStep]?
    fileprivate let definitions: [HeistPlan]
    fileprivate let diagnostics: [HeistBuildDiagnostic]

    fileprivate init(_ cases: PredicateCases, else branch: Else? = nil) {
        self.cases = cases.cases
        self.elseBody = branch?.body
        definitions = cases.definitions + (branch?.definitions ?? [])
        diagnostics = cases.diagnostics + (branch?.diagnostics ?? [])
    }
}

@resultBuilder
public enum PredicateBranchBuilder {
    public static func buildPartialBlock(first: Case) -> PredicateCases {
        PredicateCases(first)
    }

    public static func buildPartialBlock(
        accumulated: PredicateCases,
        next: Case
    ) -> PredicateCases {
        accumulated.appending(next)
    }

    public static func buildPartialBlock(
        accumulated: PredicateCases,
        next: Else
    ) -> PredicateBranches {
        PredicateBranches(accumulated, else: next)
    }

    public static func buildFinalResult(_ cases: PredicateCases) -> PredicateBranches {
        PredicateBranches(cases)
    }

    public static func buildFinalResult(_ branches: PredicateBranches) -> PredicateBranches {
        branches
    }
}

private extension ConditionalStep {
    init(cases: NonEmptyArray<PredicateCase>, elseBody: [HeistStep]? = nil) {
        self.cases = cases.elements
        self.elseBody = elseBody
    }

    init(completing step: ConditionalStep, elseBody: [HeistStep]) {
        cases = step.cases
        self.elseBody = elseBody
    }
}
