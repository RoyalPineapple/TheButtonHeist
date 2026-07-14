import ThePlans
@testable import TheInsideJob

func literalTarget(
    _ predicate: ElementPredicate,
    ordinal: Int? = nil
) -> ResolvedAccessibilityTarget {
    .predicate(predicate, ordinal: ordinal)
}

func resolvedWait(
    _ authored: WaitStep,
    in environment: HeistExecutionEnvironment = .empty
) throws -> ResolvedWaitRuntimeInput {
    try ResolvedWaitRuntimeInput(resolving: authored, in: environment)
}

func resolvedPredicate(
    _ authored: AccessibilityPredicate,
    in environment: HeistExecutionEnvironment = .empty
) throws -> ResolvedAccessibilityPredicate {
    try authored.resolve(in: environment)
}
