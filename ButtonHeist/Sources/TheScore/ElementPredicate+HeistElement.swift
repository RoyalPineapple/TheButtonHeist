import ThePlans

extension HeistElement: PredicateSelectionSubject {
    /// Known trait values. Used to reject unknown traits in predicate queries.
    private static let knownTraits = Set(HeistTrait.allCases)

    package var predicateLabel: String? { label }
    package var predicateIdentifier: String? { identifier }
    package var predicateValue: String? { value }
    package var predicateHint: String? { hint }

    package func satisfiesRequiredTraits(_ required: Set<HeistTrait>) -> Bool {
        for trait in required where !Self.knownTraits.contains(trait) { return false }
        let traitSet = Set(traits)
        return required.allSatisfy { traitSet.contains($0) }
    }

    package func satisfiesRequiredActions(_ required: Set<ElementAction>) -> Bool {
        required.isSubset(of: Set(actions))
    }

    package func containsCustomContent(matching match: CustomContentMatch<String>) -> Bool {
        CustomContentProperty.matches(match, value: customContent)
    }

    package func satisfiesRequiredRotors(_ required: [StringMatch<String>]) -> Bool {
        let names = rotors?.map(\.name) ?? []
        return required.allSatisfy { match in
            names.contains { match.matches($0) }
        }
    }

    package var predicateMatcherFacts: [AccessibilityMatcherFact] {
        AccessibilityPolicy.matcherFacts(for: self)
    }

    /// Match this wire element against an `ElementPredicate`.
    public func matches(_ predicate: ElementPredicate) -> Bool {
        predicate.matches(self)
    }
}

public extension ElementPredicate {
    /// Whether any observed element in the collection satisfies this predicate.
    func anyMatch(in elements: [HeistElement]) -> Bool {
        !ElementMatchGraph(elements: elements).resolve(self).isEmpty
    }
}

package struct ElementMatch: Sendable, Hashable {
    package let path: TreePath
    package let traversalOrder: Int
    package let element: HeistElement

    package static func == (lhs: ElementMatch, rhs: ElementMatch) -> Bool {
        lhs.path == rhs.path
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

extension ElementMatch: ElementPredicateSubjectBacked {
    package var predicateSubject: HeistElement { element }
}

package struct ElementMatchSet: Sendable, Equatable {
    package static let empty = ElementMatchSet([])

    package let matches: [ElementMatch]

    private let paths: Set<TreePath>

    package init(_ matches: [ElementMatch]) {
        var paths = Set<TreePath>()
        var uniqueMatches: [ElementMatch] = []
        uniqueMatches.reserveCapacity(matches.count)

        for match in matches where paths.insert(match.path).inserted {
            uniqueMatches.append(match)
        }

        self.matches = uniqueMatches
        self.paths = paths
    }

    package init(elements: [HeistElement]) {
        self.init(elements.enumerated().map { offset, element in
            ElementMatch(path: TreePath([offset]), traversalOrder: offset, element: element)
        })
    }

    package init(interface: Interface) {
        self.init(interface.graph.elementsInTraversalOrder.enumerated().map { offset, record in
            ElementMatch(
                path: record.path,
                traversalOrder: offset,
                element: record.projectedElement
            )
        })
    }

    package var isEmpty: Bool {
        matches.isEmpty
    }

    package var count: Int {
        matches.count
    }

    package var elements: [HeistElement] {
        matches.map(\.element)
    }

    package var orderedPaths: [TreePath] {
        matches.map(\.path)
    }

    package func intersection(_ other: ElementMatchSet) -> ElementMatchSet {
        ElementMatchSet(matches.filter { other.paths.contains($0.path) })
    }

    package func union(_ other: ElementMatchSet) -> ElementMatchSet {
        ElementMatchSet(matches + other.matches).orderedByTraversal()
    }

    private func orderedByTraversal() -> ElementMatchSet {
        ElementMatchSet(matches.sorted { $0.traversalOrder < $1.traversalOrder })
    }
}

package struct ElementMatchGraph: Sendable, Equatable {
    package let all: ElementMatchSet

    package init(_ all: ElementMatchSet) {
        self.all = all
    }

    package init(elements: [HeistElement]) {
        self.init(ElementMatchSet(elements: elements))
    }

    package init(interface: Interface) {
        self.init(ElementMatchSet(interface: interface))
    }

    package func resolve(_ predicate: ElementPredicate) -> ElementMatchSet {
        ElementMatchSet(predicateGraph.resolve(predicate).matches.map(\.subject))
    }

    package func resolve(_ target: ElementTarget) -> ElementMatchSet {
        let resolved = predicateGraph.resolve(target)
        return ElementMatchSet(resolved.matches.map(\.subject))
    }

    private var predicateGraph: ElementPredicateGraph<TreePath, ElementMatch> {
        ElementPredicateGraph(
            subjects: all.matches,
            identity: \.path,
            traversalOrder: \.traversalOrder
        )
    }
}
