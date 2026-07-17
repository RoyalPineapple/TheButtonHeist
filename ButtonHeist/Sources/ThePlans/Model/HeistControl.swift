public struct WaitFor: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlanAdmissionCandidate]
    public let heistBuildDiagnostics: [HeistBuildDiagnostic]
    private let step: WaitStep

    public init(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout = defaultWaitTimeout
    ) {
        let step = WaitStep(predicate: predicate, timeout: timeout)
        self.step = step
        heistSteps = [.wait(step)]
        heistDefinitions = []
        heistBuildDiagnostics = []
    }

    public func `else`(
        @HeistBuilder _ content: () -> some HeistContent
    ) -> some HeistContent {
        let content = content()
        return HeistStepList(
            [.wait(WaitStep(
                predicate: step.predicate,
                timeout: step.timeout,
                elseBody: content.heistSteps
            ))],
            definitions: content.heistDefinitions,
            diagnostics: content.heistBuildDiagnostics
        )
    }
}

public struct RepeatUntil: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlanAdmissionCandidate]
    public let heistBuildDiagnostics: [HeistBuildDiagnostic]
    private let step: RepeatUntilStep?

    public init(
        _ predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        let content = content()
        do {
            let step = try RepeatUntilStep(
                predicate: predicate,
                timeout: timeout,
                body: content.heistSteps
            )
            self.step = step
            heistSteps = [.repeatUntil(step)]
            heistDefinitions = content.heistDefinitions
            heistBuildDiagnostics = content.heistBuildDiagnostics
        } catch {
            self.step = nil
            heistSteps = []
            heistDefinitions = []
            heistBuildDiagnostics = content.heistBuildDiagnostics + [.dslBuild(
                code: .dslInvalidRepeatUntil,
                message: "RepeatUntil loop is invalid: \(String(describing: error))"
            )]
        }
    }

    public func `else`(
        @HeistBuilder _ content: () -> some HeistContent
    ) -> some HeistContent {
        let content = content()
        let completedSteps = step.map {
            [HeistStep.repeatUntil(RepeatUntilStep(completing: $0, elseBody: content.heistSteps))]
        } ?? []
        return HeistStepList(
            completedSteps,
            definitions: step == nil ? [] : heistDefinitions + content.heistDefinitions,
            diagnostics: heistBuildDiagnostics + content.heistBuildDiagnostics
        )
    }
}

public struct IfContent: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlanAdmissionCandidate]
    public let heistBuildDiagnostics: [HeistBuildDiagnostic]
    private let step: ConditionalStep

    public func `else`(
        @HeistBuilder _ content: () -> some HeistContent
    ) -> some HeistContent {
        let content = content()
        return HeistStepList(
            [.conditional(ConditionalStep(
                completing: step,
                elseBody: content.heistSteps
            ))],
            definitions: heistDefinitions + content.heistDefinitions,
            diagnostics: heistBuildDiagnostics + content.heistBuildDiagnostics
        )
    }

    fileprivate init(
        predicate: ChangeDeclaration.ScreenAssertion,
        content: some HeistContent
    ) {
        let step = ConditionalStep(cases: NonEmptyArray(PredicateCase(
            predicate: predicate,
            body: content.heistSteps
        )))
        self.step = step
        heistSteps = [.conditional(step)]
        heistDefinitions = content.heistDefinitions
        heistBuildDiagnostics = content.heistBuildDiagnostics
    }
}

public func If(
    _ predicate: ChangeDeclaration.ScreenAssertion,
    @HeistBuilder _ content: () -> some HeistContent
) -> IfContent {
    IfContent(predicate: predicate, content: content())
}

public func If(
    @PredicateBranchBuilder _ branches: () -> PredicateBranches
) -> some HeistContent {
    let branches = branches()
    return HeistStepList(
        [.conditional(ConditionalStep(cases: branches.cases, elseBody: branches.elseBody))],
        definitions: branches.definitions,
        diagnostics: branches.diagnostics
    )
}

public struct Case {
    fileprivate let predicateCase: PredicateCase
    fileprivate let definitions: [HeistPlanAdmissionCandidate]
    fileprivate let diagnostics: [HeistBuildDiagnostic]

    public init(
        _ predicate: ChangeDeclaration.ScreenAssertion,
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        let content = content()
        predicateCase = PredicateCase(predicate: predicate, body: content.heistSteps)
        definitions = content.heistDefinitions
        diagnostics = content.heistBuildDiagnostics
    }
}

public struct Else {
    fileprivate let body: [HeistStep]
    fileprivate let definitions: [HeistPlanAdmissionCandidate]
    fileprivate let diagnostics: [HeistBuildDiagnostic]

    public init(
        @HeistBuilder _ content: () -> some HeistContent
    ) {
        let content = content()
        body = content.heistSteps
        definitions = content.heistDefinitions
        diagnostics = content.heistBuildDiagnostics
    }
}

public struct Warn: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlanAdmissionCandidate] = []

    public init(_ message: HeistWarningMessage) {
        heistSteps = [.warn(WarnStep(message: message))]
    }
}

public struct Fail: HeistContent {
    public let heistSteps: [HeistStep]
    public let heistDefinitions: [HeistPlanAdmissionCandidate] = []

    public init(_ message: HeistFailureMessage) {
        heistSteps = [.fail(FailStep(message: message))]
    }
}

public struct PredicateCases {
    fileprivate let cases: NonEmptyArray<PredicateCase>
    fileprivate let definitions: [HeistPlanAdmissionCandidate]
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
        definitions: [HeistPlanAdmissionCandidate],
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
    fileprivate let definitions: [HeistPlanAdmissionCandidate]
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

private extension RepeatUntilStep {
    init(completing step: RepeatUntilStep, elseBody: [HeistStep]) {
        predicate = step.predicate
        timeout = step.timeout
        body = step.body
        self.elseBody = elseBody
    }
}
