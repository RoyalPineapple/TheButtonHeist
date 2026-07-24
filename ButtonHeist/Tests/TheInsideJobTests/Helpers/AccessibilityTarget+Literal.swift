import ThePlans
@testable import TheInsideJob

func literalTarget(
    _ predicate: ResolvedElementPredicate,
    ordinal: Int? = nil
) -> ResolvedAccessibilityTarget {
    .predicate(predicate, ordinal: ordinal)
}

extension TheVault.TargetResolution {
    var resolvedElement: InterfaceTree.Element? {
        guard case .resolved(.element(let element)) = self else {
            return nil
        }
        return element
    }
}

func resolvedPredicate(
    _ authored: AccessibilityPredicate,
    in environment: HeistExecutionEnvironment = .empty
) throws -> ResolvedAccessibilityPredicate {
    try authored.resolve(in: environment)
}
