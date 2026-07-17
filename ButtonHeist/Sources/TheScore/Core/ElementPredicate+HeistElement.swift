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
        !AccessibilityTargetMatchGraph(elements: elements).resolve(self).isEmpty
    }
}

package struct AccessibilityTargetElementMatch: Sendable, Equatable {
    package let path: TreePath
    package let traversalOrder: Int
    package let parentContainerPath: TreePath?
    package let element: HeistElement

    package init(path: TreePath, traversalOrder: Int, parentContainerPath: TreePath?, element: HeistElement) {
        self.path = path
        self.traversalOrder = traversalOrder
        self.parentContainerPath = parentContainerPath
        self.element = element
    }
}

extension AccessibilityTargetElementMatch: ElementPredicateSubjectBacked {
    package var predicateSubject: HeistElement { element }
}

package struct AccessibilityTargetElementMatchSet: Sendable, Equatable {
    package static let empty = Self([])
    package let matches: [AccessibilityTargetElementMatch]
    private let traversalOrders: Set<Int>

    package init(_ matches: [AccessibilityTargetElementMatch]) {
        var traversalOrders = Set<Int>()
        self.matches = matches.filter { traversalOrders.insert($0.traversalOrder).inserted }
        self.traversalOrders = traversalOrders
    }

    package var isEmpty: Bool { matches.isEmpty }
    package var count: Int { matches.count }
    package var elements: [HeistElement] { matches.map(\.element) }
    package var orderedPaths: [TreePath] { matches.map(\.path) }

    package func intersection(_ other: Self) -> Self {
        Self(matches.filter { other.traversalOrders.contains($0.traversalOrder) })
    }

    package func union(_ other: Self) -> Self {
        Self(matches + other.matches).orderedByTraversal()
    }

    private func orderedByTraversal() -> Self {
        Self(matches.sorted { $0.traversalOrder < $1.traversalOrder })
    }
}

package struct AccessibilityTargetContainerMatch: Sendable, Equatable {
    package let path: TreePath
    package let parentContainerPath: TreePath?
    package let facts: ContainerPredicateFacts

    package init(path: TreePath, parentContainerPath: TreePath?, facts: ContainerPredicateFacts) {
        self.path = path
        self.parentContainerPath = parentContainerPath
        self.facts = facts
    }
}

package struct AccessibilityTargetMatchInput: Sendable, Equatable {
    package let elements: [AccessibilityTargetElementMatch]
    package let containers: [AccessibilityTargetContainerMatch]

    package init(elements: [AccessibilityTargetElementMatch], containers: [AccessibilityTargetContainerMatch]) {
        self.elements = elements
        self.containers = containers
    }

    package init(elements: [HeistElement]) {
        self.init(elements: elements.enumerated().map { offset, element in
            AccessibilityTargetElementMatch(
                path: TreePath([offset]),
                traversalOrder: offset,
                parentContainerPath: nil,
                element: element
            )
        }, containers: [])
    }

    package init(interface: Interface) {
        let containerRecords = interface.graph.nodesInPathOrder.compactMap { record -> InterfaceGraphContainerRecord? in
            guard case .container(let container) = record.kind else { return nil }
            return container
        }
        let containerPaths = Set(containerRecords.map(\.path))
        self.init(
            elements: interface.graph.elementsInTraversalOrder.enumerated().map { offset, record in
                AccessibilityTargetElementMatch(
                    path: record.path,
                    traversalOrder: offset,
                    parentContainerPath: Self.parentContainerPath(for: record.path, among: containerPaths),
                    element: record.projectedElement
                )
            },
            containers: containerRecords.map { record in
                AccessibilityTargetContainerMatch(
                    path: record.path,
                    parentContainerPath: Self.parentContainerPath(for: record.path, among: containerPaths),
                    facts: record.container.containerPredicateFacts
                )
            }
        )
    }

    package static func parentContainerPath(
        for path: TreePath,
        preferred: TreePath? = nil,
        among containerPaths: Set<TreePath>
    ) -> TreePath? {
        if let preferred, containerPaths.contains(preferred) { return preferred }
        var parent = path.parent
        while let candidate = parent, candidate != .root {
            if containerPaths.contains(candidate) { return candidate }
            parent = candidate.parent
        }
        return nil
    }
}

package enum AccessibilityTargetTerminalSelection: Sendable {
    case element(predicate: ElementPredicate, ordinal: Int?)
    case container(predicate: ResolvedContainerPredicate, ordinal: Int?)

    fileprivate var ordinal: Int? {
        switch self {
        case .element(_, let ordinal), .container(_, let ordinal): ordinal
        }
    }
}

package extension ResolvedAccessibilityTarget {
    var terminalSelection: AccessibilityTargetTerminalSelection {
        switch self {
        case .predicate(let predicate, let ordinal): .element(predicate: predicate, ordinal: ordinal)
        case .container(let predicate, let ordinal): .container(predicate: predicate, ordinal: ordinal)
        case .within(_, let target): target.terminalSelection
        }
    }

    var isElementTarget: Bool {
        if case .element = terminalSelection { return true }
        return false
    }
}

package struct AccessibilityTargetMatchGraph: Sendable, Equatable {
    package let all: AccessibilityTargetElementMatchSet
    private let containers: [AccessibilityTargetContainerMatch]
    private let parentContainerPathByPath: [TreePath: TreePath]

    package init(_ input: AccessibilityTargetMatchInput) {
        self.init(
            all: AccessibilityTargetElementMatchSet(input.elements),
            containers: input.containers,
            parentContainerPathByPath: Dictionary(
                uniqueKeysWithValues: input.containers.compactMap { match in
                    match.parentContainerPath.map { (match.path, $0) }
                }
            )
        )
    }

    private init(
        all: AccessibilityTargetElementMatchSet,
        containers: [AccessibilityTargetContainerMatch],
        parentContainerPathByPath: [TreePath: TreePath]
    ) {
        self.all = all
        self.containers = containers
        self.parentContainerPathByPath = parentContainerPathByPath
    }

    package init(elements: [HeistElement]) {
        self.init(AccessibilityTargetMatchInput(elements: elements))
    }

    package init(interface: Interface) {
        self.init(AccessibilityTargetMatchInput(interface: interface))
    }

    package func resolve(_ predicate: ElementPredicate) -> AccessibilityTargetElementMatchSet {
        AccessibilityTargetElementMatchSet(predicateGraph.resolve(predicate).matches.map(\.subject))
    }

    package func resolve(_ target: ResolvedAccessibilityTarget) -> AccessibilityTargetMatchSet {
        matches(for: target).selecting(ordinal: target.terminalSelection.ordinal)
    }

    package func matches(for target: ResolvedAccessibilityTarget) -> AccessibilityTargetMatchSet {
        switch target {
        case .predicate(let predicate, _):
            let matches = predicateGraph.resolve(predicate).matches.map(\.subject)
            return AccessibilityTargetMatchSet(elements: AccessibilityTargetElementMatchSet(matches))
        case .container(let predicate, _):
            return AccessibilityTargetMatchSet(containerPaths: containers.paths(matching: predicate))
        case .within(let container, let nestedTarget):
            return scoped(to: container).matches(for: nestedTarget)
        }
    }

    package func elementCandidates(in target: ResolvedAccessibilityTarget) -> AccessibilityTargetElementMatchSet {
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
        containers.contains { predicate.matches($0.facts) }
    }

    private func scoped(to predicate: ResolvedContainerPredicate) -> AccessibilityTargetMatchGraph {
        let containerPaths = Set(containers
            .filter { predicate.matches($0.facts) }
            .map(\.path))
        return AccessibilityTargetMatchGraph(
            all: AccessibilityTargetElementMatchSet(
                all.matches.filter { isContained(parent: $0.parentContainerPath, in: containerPaths) }
            ),
            containers: containers.filter {
                containerPaths.contains($0.path) || isContained(parent: $0.parentContainerPath, in: containerPaths)
            },
            parentContainerPathByPath: parentContainerPathByPath
        )
    }

    private func isContained(parent: TreePath?, in containerPaths: Set<TreePath>) -> Bool {
        var candidate = parent
        var visited = Set<TreePath>()
        while let path = candidate, visited.insert(path).inserted {
            if containerPaths.contains(path) { return true }
            candidate = parentContainerPathByPath[path]
        }
        return false
    }

    private var predicateGraph: ElementPredicateGraph<Int, AccessibilityTargetElementMatch> {
        ElementPredicateGraph(
            subjects: all.matches,
            identity: \.traversalOrder,
            traversalOrder: \.traversalOrder
        )
    }
}

package struct AccessibilityTargetMatchSet: Sendable, Equatable {
    package static let empty = AccessibilityTargetMatchSet()

    package let elements: AccessibilityTargetElementMatchSet
    package let containerPaths: [TreePath]

    package init(
        elements: AccessibilityTargetElementMatchSet = .empty,
        containerPaths: [TreePath] = []
    ) {
        self.elements = elements
        self.containerPaths = containerPaths
    }

    package var isEmpty: Bool { elements.isEmpty && containerPaths.isEmpty }
    package var paths: Set<TreePath> { Set(elements.orderedPaths).union(containerPaths) }
    package var orderedPaths: [TreePath] { elements.isEmpty ? containerPaths : elements.orderedPaths }

    fileprivate func selecting(ordinal: Int?) -> Self {
        guard let ordinal else { return self }
        if !elements.isEmpty {
            guard elements.matches.indices.contains(ordinal) else { return .empty }
            return Self(elements: AccessibilityTargetElementMatchSet([elements.matches[ordinal]]))
        }
        guard containerPaths.indices.contains(ordinal) else { return .empty }
        return Self(containerPaths: [containerPaths[ordinal]])
    }
}

private extension Array where Element == AccessibilityTargetContainerMatch {
    func paths(matching predicate: ResolvedContainerPredicate) -> [TreePath] {
        [TreePath](lazy.filter { predicate.matches($0.facts) }.map { $0.path })
    }
}
