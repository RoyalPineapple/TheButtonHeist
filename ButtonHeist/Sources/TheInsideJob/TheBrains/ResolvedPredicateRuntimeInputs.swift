#if canImport(UIKit)
#if DEBUG
import ThePlans

struct ResolvedWaitRuntimeInput: Sendable, Equatable {
    let predicateExpression: AccessibilityPredicate
    let predicate: ResolvedAccessibilityPredicate
    let timeout: WaitTimeout

    init(resolving authored: WaitStep, in environment: HeistExecutionEnvironment) throws {
        self.init(
            predicateExpression: authored.predicate,
            predicate: try authored.predicate.resolve(in: environment),
            timeout: authored.timeout
        )
    }

    init(
        repeatUntil step: ResolvedRepeatUntilStep,
        timeout: WaitTimeout
    ) {
        self.init(
            predicateExpression: step.predicateExpression,
            predicate: step.predicate,
            timeout: timeout
        )
    }

    static func changedElements(timeout: WaitTimeout) -> ResolvedWaitRuntimeInput {
        ResolvedWaitRuntimeInput(
            predicateExpression: .changed(.elements()),
            predicate: .changed(.elements([])),
            timeout: timeout
        )
    }

    private init(
        predicateExpression: AccessibilityPredicate,
        predicate: ResolvedAccessibilityPredicate,
        timeout: WaitTimeout
    ) {
        self.predicateExpression = predicateExpression
        self.predicate = predicate
        self.timeout = timeout
    }
}

struct ResolvedPredicateCaseRuntimeInput: Sendable, Equatable {
    let predicateExpression: ChangeDeclaration.ScreenAssertion
    let predicate: ResolvedScreenAssertion
    let body: [HeistStep]

    init(resolving authored: PredicateCase, in environment: HeistExecutionEnvironment) throws {
        self.predicateExpression = authored.predicate
        self.predicate = try authored.predicate.resolve(in: environment)
        self.body = authored.body
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
