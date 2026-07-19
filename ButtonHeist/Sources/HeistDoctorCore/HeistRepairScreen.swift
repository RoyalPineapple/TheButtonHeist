import ThePlans
import TheScore

// MARK: - Repair Screen

private typealias RepairPredicateElement = PredicateSelectionSubjectElement<HeistElement>

struct RepairScreen {
    struct Element: Sendable, Equatable {
        let id: PredicateSelectionElementId
        let element: HeistElement
        let path: TreePath
        let traversalIndex: Int
        let siblingText: [String]
        let headerText: [String]

        var repairContext: HeistRepairElementContext {
            HeistRepairElementContext(
                element: element,
                siblingText: siblingText,
                headerText: headerText
            )
        }
    }

    let elements: [Element]
    private let targetMatchGraph: AccessibilityTargetMatchGraph<HeistElement>
    private let predicateSelectionElements: [RepairPredicateElement]

    init(interface: Interface) {
        let indexed = interface.graph.elementsInTraversalOrder.enumerated().map { ordinal, record in
            ElementCore(
                id: PredicateSelectionElementId(rawValue: "element-\(ordinal)"),
                element: record.projectedElement,
                path: record.path,
                traversalIndex: record.traversalIndex,
                primaryText: primaryText(record.projectedElement)
            )
        }
        let siblingGroups = Dictionary(grouping: indexed) { parentPath($0.path) }
            .mapValues { SiblingTextGroup($0) }
        var headers: [String] = []
        var elements: [Element] = []
        elements.reserveCapacity(indexed.count)

        for core in indexed {
            let element = Element(
                id: core.id,
                element: core.element,
                path: core.path,
                traversalIndex: core.traversalIndex,
                siblingText: siblingGroups[parentPath(core.path)]?.excluding(core.primaryText) ?? [],
                headerText: Array(headers.suffix(3))
            )
            if core.element.traits.contains(.header), let header = core.primaryText {
                headers.append(header)
            }
            elements.append(element)
        }

        let predicateSelectionElements = elements.map {
            PredicateSelectionSubjectElement(id: $0.id, element: $0.element)
        }
        self.elements = elements
        self.targetMatchGraph = AccessibilityTargetMatchGraph(interface: interface)
        self.predicateSelectionElements = predicateSelectionElements
    }

    func resolve(_ target: AccessibilityTarget) -> RepairTargetResolution {
        let resolvedTarget: ResolvedAccessibilityTarget
        do {
            resolvedTarget = try target.resolve(in: .empty)
        } catch HeistExpressionError.unresolvedTargetReference {
            return .unsupportedTarget(.reference)
        } catch {
            return .unsupportedTarget(.unresolvedExpression)
        }

        let candidates = repairElements(at: targetMatchGraph.matches(for: resolvedTarget).elements.orderedPaths)
        let selected = repairElements(at: targetMatchGraph.resolve(resolvedTarget).elements.orderedPaths)
        guard resolvedTarget.isElementTarget else {
            return .unsupportedTarget(.container)
        }

        if candidates.count > 1, selected.count == candidates.count {
            return .ambiguous(candidates, matchCount: candidates.count)
        }
        if let match = selected.first {
            return .resolved(match, matchCount: candidates.count)
        }
        return .notFound(matchCount: candidates.count)
    }

    private func repairElements(at paths: [TreePath]) -> [Element] {
        let paths = Set(paths)
        return elements.filter { paths.contains($0.path) }
    }

    func minimumUniquePredicate(
        for elementId: PredicateSelectionElementId
    ) -> MinimumPredicateSelection? {
        MinimumPredicateSelector.minimumUniquePredicate(
            for: elementId,
            in: predicateSelectionElements
        )
    }
}

private struct ElementCore {
    let id: PredicateSelectionElementId
    let element: HeistElement
    let path: TreePath
    let traversalIndex: Int
    let primaryText: String?
}

private struct SiblingTextGroup {
    private let orderedUniqueText: [String]
    private let occurrenceCount: [String: Int]

    init(_ elements: [ElementCore]) {
        var orderedUniqueText: [String] = []
        var occurrenceCount: [String: Int] = [:]
        orderedUniqueText.reserveCapacity(elements.count)
        occurrenceCount.reserveCapacity(elements.count)

        for text in elements.compactMap(\.primaryText) {
            let count = occurrenceCount[text, default: 0]
            if count == 0 {
                orderedUniqueText.append(text)
            }
            occurrenceCount[text] = count + 1
        }

        self.orderedUniqueText = orderedUniqueText
        self.occurrenceCount = occurrenceCount
    }

    func excluding(_ text: String?) -> [String] {
        guard let text, occurrenceCount[text] == 1 else {
            return orderedUniqueText
        }
        return orderedUniqueText.filter { $0 != text }
    }
}

enum RepairTargetResolution {
    case resolved(RepairScreen.Element, matchCount: Int)
    case notFound(matchCount: Int)
    case ambiguous([RepairScreen.Element], matchCount: Int)
    case unsupportedTarget(UnsupportedRepairTargetKind)
}

enum UnsupportedRepairTargetKind: String, Sendable, Equatable {
    case container
    case reference
    case unresolvedExpression
}

private func parentPath(_ path: TreePath) -> TreePath {
    path.parent ?? .root
}
