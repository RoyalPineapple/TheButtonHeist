/// The before/after shape shared by every property-change case.
package struct PropertyChangeCore<Checker> {
    package let before: Checker?
    package let after: Checker?

    package init(before: Checker? = nil, after: Checker? = nil) {
        self.before = before
        self.after = after
    }

    package func map<NewChecker>(
        _ transform: (Checker) throws -> NewChecker
    ) rethrows -> PropertyChangeCore<NewChecker> {
        try PropertyChangeCore<NewChecker>(
            before: before.map(transform),
            after: after.map(transform)
        )
    }
}

extension PropertyChangeCore: Sendable where Checker: Sendable {}
extension PropertyChangeCore: Equatable where Checker: Equatable {}
