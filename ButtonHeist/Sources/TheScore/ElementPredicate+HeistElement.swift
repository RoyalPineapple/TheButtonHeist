import ThePlans

extension HeistElement: ElementPredicateSubject {
    /// Known trait values. Used to reject unknown traits in predicate queries.
    private static let knownTraits = Set(HeistTrait.allCases)

    public var predicateLabel: String? { label }
    public var predicateIdentifier: String? { identifier }
    public var predicateValue: String? { value }

    public func satisfiesRequiredTraits(_ required: [HeistTrait]) -> Bool {
        for trait in required where !Self.knownTraits.contains(trait) { return false }
        let traitSet = Set(traits)
        return required.allSatisfy { traitSet.contains($0) }
    }

    public func violatesExcludedTraits(_ excluded: [HeistTrait]) -> Bool {
        for trait in excluded where !Self.knownTraits.contains(trait) { return true }
        let traitSet = Set(traits)
        return excluded.contains { traitSet.contains($0) }
    }

    /// Match this wire element against an `ElementPredicate`.
    public func matches(_ predicate: ElementPredicate) -> Bool {
        predicate.matches(self)
    }
}

public extension ElementPredicate {
    /// Whether any observed element in the collection satisfies this predicate.
    func anyMatch(in elements: [HeistElement]) -> Bool {
        elements.contains { matches($0) }
    }
}
