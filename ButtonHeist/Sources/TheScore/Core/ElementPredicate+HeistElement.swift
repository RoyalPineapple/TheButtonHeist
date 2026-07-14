import AccessibilitySnapshotModel
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

    package func containsCustomContent(matching match: CustomContentMatchCore<String>) -> Bool {
        guard let customContent else { return false }
        return customContent.contains { content in
            match.label.matches(content.label)
                && match.value.matches(content.value)
                && (match.isImportant.map { $0 == content.isImportant } ?? true)
        }
    }

    package func satisfiesRequiredRotors(_ required: [StringMatchCore<String>]) -> Bool {
        let names = rotors?.map(\.name) ?? []
        return required.allSatisfy { match in
            names.contains { ResolvedStringMatch(core: match).matches($0) }
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

private extension Optional where Wrapped == StringMatchCore<String> {
    func matches(_ text: String) -> Bool {
        map { ResolvedStringMatch(core: $0).matches(text) } ?? true
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

private struct ContainerMatch: Sendable, Equatable {
    let path: TreePath
    let traversalOrder: Int
    let facts: ContainerPredicateFacts

    static func == (lhs: ContainerMatch, rhs: ContainerMatch) -> Bool {
        lhs.path == rhs.path
    }
}

private struct ContainerMatchSet: Sendable, Equatable {
    static let empty = ContainerMatchSet([])

    let matches: [ContainerMatch]

    init(_ matches: [ContainerMatch]) {
        var paths = Set<TreePath>()
        var uniqueMatches: [ContainerMatch] = []
        uniqueMatches.reserveCapacity(matches.count)

        for match in matches where paths.insert(match.path).inserted {
            uniqueMatches.append(match)
        }

        self.matches = uniqueMatches
    }

    init(interface: Interface) {
        self.init(interface.graph.nodesInPathOrder.enumerated().compactMap { offset, record in
            guard case .container(let container) = record.kind else { return nil }
            return ContainerMatch(
                path: container.path,
                traversalOrder: offset,
                facts: container.container.containerPredicateFacts
            )
        })
    }

    var orderedPaths: [TreePath] {
        matches.map(\.path)
    }

}

package struct ElementMatchGraph: Sendable, Equatable {
    package let all: ElementMatchSet
    private let containers: ContainerMatchSet

    package init(_ all: ElementMatchSet) {
        self.all = all
        self.containers = .empty
    }

    private init(all: ElementMatchSet, containers: ContainerMatchSet) {
        self.all = all
        self.containers = containers
    }

    package init(elements: [HeistElement]) {
        self.init(ElementMatchSet(elements: elements))
    }

    package init(interface: Interface) {
        self.init(
            all: ElementMatchSet(interface: interface),
            containers: ContainerMatchSet(interface: interface)
        )
    }

    package func resolve(_ predicate: ElementPredicate) -> ElementMatchSet {
        ElementMatchSet(predicateGraph.resolve(predicate).matches.map(\.subject))
    }

    package func resolve(_ target: ResolvedAccessibilityTarget) -> AccessibilityTargetMatchSet {
        switch target {
        case .predicate(let predicate, let ordinal):
            let matches = predicateGraph.resolve(predicate).matches.map(\.subject)
            if let ordinal {
                guard matches.indices.contains(ordinal) else { return .empty }
                return AccessibilityTargetMatchSet(elements: ElementMatchSet([matches[ordinal]]))
            }
            return AccessibilityTargetMatchSet(elements: ElementMatchSet(matches))
        case .container(let predicate, let ordinal):
            let paths = containers.paths(matching: predicate)
            if let ordinal {
                guard paths.indices.contains(ordinal) else { return .empty }
                return AccessibilityTargetMatchSet(containerPaths: [paths[ordinal]])
            }
            return AccessibilityTargetMatchSet(containerPaths: paths)
        case .within(let container, let nestedTarget):
            return scoped(to: container).resolve(nestedTarget)
        }
    }

    package func elementCandidates(in target: ResolvedAccessibilityTarget) -> ElementMatchSet {
        switch target {
        case .predicate:
            return all
        case .container:
            return .empty
        case .within(let container, let nestedTarget):
            return scoped(to: container).elementCandidates(in: nestedTarget)
        }
    }

    package func containsContainer(matching predicate: ResolvedContainerPredicate) -> Bool {
        containers.matches.contains { predicate.matches($0.facts) }
    }

    private func scoped(to predicate: ResolvedContainerPredicate) -> ElementMatchGraph {
        let containerPaths = containers.matches
            .filter { predicate.matches($0.facts) }
            .map(\.path)
        guard !containerPaths.isEmpty else {
            return ElementMatchGraph(all: .empty, containers: .empty)
        }
        return ElementMatchGraph(
            all: ElementMatchSet(all.matches.filter { match in
                containerPaths.contains { match.path.hasPrefix($0) }
            }),
            containers: ContainerMatchSet(containers.matches.filter { match in
                containerPaths.contains { match.path.hasPrefix($0) }
            })
        )
    }

    private var predicateGraph: ElementPredicateGraph<TreePath, ElementMatch> {
        ElementPredicateGraph(
            subjects: all.matches,
            identity: \.path,
            traversalOrder: \.traversalOrder
        )
    }
}

package struct AccessibilityTargetMatchSet: Sendable, Equatable {
    package static let empty = AccessibilityTargetMatchSet()

    package let elements: ElementMatchSet
    package let containerPaths: [TreePath]

    package init(
        elements: ElementMatchSet = .empty,
        containerPaths: [TreePath] = []
    ) {
        self.elements = elements
        self.containerPaths = containerPaths
    }

    package var isEmpty: Bool {
        elements.isEmpty && containerPaths.isEmpty
    }

    package var paths: Set<TreePath> {
        Set(elements.orderedPaths).union(containerPaths)
    }

    package var orderedPaths: [TreePath] {
        elements.isEmpty ? containerPaths : elements.orderedPaths
    }
}

private extension ContainerMatchSet {
    func paths(matching predicate: ResolvedContainerPredicate) -> [TreePath] {
        Array(matches.lazy.filter { predicate.matches($0.facts) }.map(\.path))
    }
}
