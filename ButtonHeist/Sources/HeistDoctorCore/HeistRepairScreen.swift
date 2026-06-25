import ThePlans
import TheScore

// MARK: - Repair Screen

struct RepairScreen {
    struct Element: Sendable, Equatable {
        let id: PredicateSelectionElementId
        let element: HeistElement
        let path: TreePath
        let traversalIndex: Int
        let ordinal: Int
        let siblingText: [String]
        let headerText: [String]

        var summary: ElementSummary {
            ElementSummary(
                description: element.description,
                label: nonEmpty(element.label),
                value: nonEmpty(element.value),
                identifier: stableIdentifier(element.identifier),
                hint: nonEmpty(element.hint),
                traits: element.traits,
                actions: element.actions,
                rotors: element.rotors?.map(\.name) ?? [],
                siblingText: siblingText,
                headerText: headerText
            )
        }
    }

    let elements: [Element]

    init(interface: Interface) {
        let annotationsByPath = interface.annotations.elementByPath
        let indexed = interface.tree.pathIndexedElements.enumerated().map { ordinal, item in
            ElementCore(
                id: PredicateSelectionElementId(rawValue: "element-\(ordinal)"),
                element: HeistElement(
                    accessibilityElement: item.element,
                    annotation: annotationsByPath[item.path]
                ),
                path: item.path,
                traversalIndex: item.traversalIndex,
                ordinal: ordinal
            )
        }
        let siblingsByParent = Dictionary(grouping: indexed) { parentPath($0.path) }
        var headers: [String] = []
        var elements: [Element] = []
        elements.reserveCapacity(indexed.count)

        for core in indexed {
            let siblings = (siblingsByParent[parentPath(core.path)] ?? [])
                .filter { $0.id != core.id }
                .compactMap { primaryText($0.element) }
            let element = Element(
                id: core.id,
                element: core.element,
                path: core.path,
                traversalIndex: core.traversalIndex,
                ordinal: core.ordinal,
                siblingText: unique(siblings),
                headerText: Array(headers.suffix(3))
            )
            if core.element.traits.contains(.header), let header = primaryText(core.element) {
                headers.append(header)
            }
            elements.append(element)
        }
        self.elements = elements
    }

    func resolve(_ target: ElementTarget) -> RepairTargetResolution {
        switch target {
        case .predicate(let predicate, let ordinal):
            let matches = elements.filter { $0.element.matches(predicate) }
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
        }
    }

    func selectionContext() -> PredicateSelectionContext {
        PredicateSelectionContext(
            elements: elements.map {
                PredicateSelectionContext.Element(id: $0.id, element: $0.element)
            },
            scope: .discovery
        )
    }
}

private struct ElementCore {
    let id: PredicateSelectionElementId
    let element: HeistElement
    let path: TreePath
    let traversalIndex: Int
    let ordinal: Int
}

enum RepairTargetResolution {
    case resolved(RepairScreen.Element, matchCount: Int)
    case notFound(matchCount: Int)
    case ambiguous([RepairScreen.Element], matchCount: Int)
}

private func parentPath(_ path: TreePath) -> TreePath {
    guard !path.indices.isEmpty else { return TreePath.root }
    return TreePath(Array(path.indices.dropLast()))
}
