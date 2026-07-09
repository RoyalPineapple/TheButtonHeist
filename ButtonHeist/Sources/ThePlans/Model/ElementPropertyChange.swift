// MARK: - Element Property Changes

/// A before/after predicate for one property. The generic property kind locks
/// both sides to the same checker type and derives the wire property name.
public struct ElementPropertyChange<P: ElementPropertyKind>: Sendable, Equatable {
    public let before: P.Checker?
    public let after: P.Checker?
    public var property: ElementProperty { P.property }

    public init(before: P.Checker? = nil, after: P.Checker? = nil) {
        self.before = before
        self.after = after
    }
}

/// Source-time variant of `ElementPropertyChange`, preserving string refs until
/// a heist executes.
public struct ElementPropertyChangeExpr<P: ElementPropertyKind>: Sendable, Equatable {
    public let before: P.ExprChecker?
    public let after: P.ExprChecker?
    public var property: ElementProperty { P.property }

    public init(before: P.ExprChecker? = nil, after: P.ExprChecker? = nil) {
        self.before = before
        self.after = after
    }
}
