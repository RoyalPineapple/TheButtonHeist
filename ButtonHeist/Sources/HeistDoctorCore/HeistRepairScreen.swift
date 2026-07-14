import ThePlans
import TheScore

// MARK: - Repair Screen

private typealias RepairPredicateElement = PredicateSelectionSubjectElement<HeistElement>
private typealias RepairPredicateGraph = ElementPredicateGraph<PredicateSelectionElementId, RepairPredicateElement>

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
    private let predicateGraph: RepairPredicateGraph
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
        self.predicateGraph = ElementPredicateGraph(
            subjects: predicateSelectionElements,
            identity: \.id
        )
        self.predicateSelectionElements = predicateSelectionElements
    }

    func resolve(_ target: AccessibilityTarget) -> RepairTargetResolution {
        switch target {
        case .predicate(let predicate, let ordinal):
            let resolvedPredicate: ElementPredicate
            do {
                resolvedPredicate = try predicate.resolve(in: .empty)
            } catch {
                return .unsupportedTarget(.unresolvedExpression)
            }
            let matches = predicateGraph
                .resolve(resolvedPredicate)
                .matches
                .map { elements[$0.traversalOrder] }
            if let ordinal {
                guard matches.indices.contains(ordinal) else {
                    return .notFound(matchCount: matches.count)
                }
                return .resolved(matches[ordinal], matchCount: matches.count)
            }
            switch matches.count {
            case 0:
                return .notFound(matchCount: 0)
            case 1:
                return .resolved(matches[0], matchCount: 1)
            default:
                return .ambiguous(matches, matchCount: matches.count)
            }
        case .container:
            return .unsupportedTarget(.container)
        case .ref:
            return .unsupportedTarget(.reference)
        case .within:
            return .unsupportedTarget(.scoped)
        }
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
    case scoped
    case unresolvedExpression
}

private func parentPath(_ path: TreePath) -> TreePath {
    path.parent ?? .root
}
