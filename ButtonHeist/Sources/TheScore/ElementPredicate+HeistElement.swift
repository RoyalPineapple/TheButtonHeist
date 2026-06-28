import ThePlans

extension HeistElement: ElementPredicateSubject {
    /// Known trait values. Used to reject unknown traits in predicate queries.
    private static let knownTraits = Set(HeistTrait.allCases)

    package var predicateLabel: String? { label }
    package var predicateIdentifier: String? { identifier }
    package var predicateValue: String? { value }

    package func satisfiesRequiredTraits(_ required: Set<HeistTrait>) -> Bool {
        for trait in required where !Self.knownTraits.contains(trait) { return false }
        let traitSet = Set(traits)
        return required.allSatisfy { traitSet.contains($0) }
    }

    package func violatesExcludedTraits(_ excluded: Set<HeistTrait>) -> Bool {
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
        !ElementMatchSet(elements: elements).matching(self).isEmpty
    }
}

struct ElementMatch: Sendable, Hashable {
    let path: TreePath
    let traversalOrder: Int
    let element: HeistElement

    static func == (lhs: ElementMatch, rhs: ElementMatch) -> Bool {
        lhs.path == rhs.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

struct ElementMatchSet: Sendable, Equatable {
    static let empty = ElementMatchSet([])

    let matches: [ElementMatch]

    private let paths: Set<TreePath>

    init(_ matches: [ElementMatch]) {
        var paths = Set<TreePath>()
        var uniqueMatches: [ElementMatch] = []
        uniqueMatches.reserveCapacity(matches.count)

        for match in matches where paths.insert(match.path).inserted {
            uniqueMatches.append(match)
        }

        self.matches = uniqueMatches
        self.paths = paths
    }

    init(elements: [HeistElement]) {
        self.init(elements.enumerated().map { offset, element in
            ElementMatch(path: TreePath([offset]), traversalOrder: offset, element: element)
        })
    }

    init(interface: Interface) {
        let annotationsByPath = interface.annotations.elementByPath
        self.init(interface.tree.pathIndexedElements.enumerated().map { offset, item in
            ElementMatch(
                path: item.path,
                traversalOrder: offset,
                element: HeistElement(
                    accessibilityElement: item.element,
                    annotation: annotationsByPath[item.path]
                )
            )
        })
    }

    var isEmpty: Bool {
        matches.isEmpty
    }

    var count: Int {
        matches.count
    }

    var elements: [HeistElement] {
        matches.map(\.element)
    }

    var orderedPaths: [TreePath] {
        matches.map(\.path)
    }

    func intersection(_ other: ElementMatchSet) -> ElementMatchSet {
        ElementMatchSet(matches.filter { other.paths.contains($0.path) })
    }

    func union(_ other: ElementMatchSet) -> ElementMatchSet {
        ElementMatchSet(matches + other.matches).orderedByTraversal()
    }

    func matching(_ predicate: ElementPredicate) -> ElementMatchSet {
        guard predicate.hasPredicates else { return .empty }
        guard let firstCheck = predicate.checks.first else { return .empty }

        let firstMatches = matching(firstCheck)
        return predicate.checks.dropFirst().reduce(firstMatches) { narrowedMatches, check in
            narrowedMatches.intersection(self.matching(check))
        }
    }

    func matching(_ target: ElementTarget) -> ElementMatchSet {
        switch target {
        case .predicate(let predicate, let ordinal):
            let predicateMatches = matching(predicate)
            guard let ordinal else { return predicateMatches }
            guard predicateMatches.matches.indices.contains(ordinal) else { return .empty }
            return ElementMatchSet([predicateMatches.matches[ordinal]])
        }
    }

    private func matching(_ check: ElementPredicateCheck<String>) -> ElementMatchSet {
        ElementMatchSet(matches.filter { check.matches($0.element) })
    }

    private func orderedByTraversal() -> ElementMatchSet {
        ElementMatchSet(matches.sorted {
            if $0.traversalOrder != $1.traversalOrder {
                return $0.traversalOrder < $1.traversalOrder
            }
            return $0.path < $1.path
        })
    }
}
