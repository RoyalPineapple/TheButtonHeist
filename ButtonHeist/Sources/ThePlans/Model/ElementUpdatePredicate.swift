// MARK: - Element Update Predicate

/// Predicate over a single element-property change in a baseline-to-current
/// transition.
///
/// `element` is an orthogonal identity matcher for the paired element.
/// `change` names at most one changed property. Its generic property kind locks
/// before and after to the same checker type, so contradictory predicates such
/// as "value before/after but property traits" are unrepresentable in Swift.
public struct ElementUpdatePredicate: Sendable, Equatable {
    public let element: ElementPredicate?
    public let change: AnyPropertyChange?

    public init(
        element: ElementPredicate? = nil,
        change: AnyPropertyChange? = nil
    ) {
        self.element = element
        self.change = change
    }

    /// Any tracked element property changed (all filters unset).
    public static let any = ElementUpdatePredicate()
}

public struct ElementUpdatePredicateExpr: Sendable, Equatable {
    public let element: ElementPredicateTemplate?
    public let change: AnyPropertyChangeExpr?

    public init(
        element: ElementPredicateTemplate? = nil,
        change: AnyPropertyChangeExpr? = nil
    ) {
        self.element = element
        self.change = change
    }

    public init(_ update: ElementUpdatePredicate) {
        self.init(
            element: update.element.map(ElementPredicateTemplate.init),
            change: update.change.map(AnyPropertyChangeExpr.init)
        )
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementUpdatePredicate {
        try ElementUpdatePredicate(
            element: element?.resolve(in: environment),
            change: change?.resolve(in: environment)
        )
    }
}

// MARK: - Element Delta Predicate

/// Predicate over one same-screen element delta.
///
/// These predicates reuse the same `ElementPredicate` and string matching
/// machinery as targeting. The only difference is the side of the delta they
/// are evaluated against:
/// - `appeared`: matches an element absent from the baseline and present in the
///   final tree.
/// - `disappeared`: matches an element present in the baseline and absent from
///   the final tree.
/// - `updated`: matches a paired element whose tracked properties changed.
public enum ElementDeltaPredicate: Sendable, Equatable {
    case appearedElement(ElementPredicate)
    case disappearedElement(ElementPredicate)
    case updatedElement(ElementUpdatePredicate)
}
