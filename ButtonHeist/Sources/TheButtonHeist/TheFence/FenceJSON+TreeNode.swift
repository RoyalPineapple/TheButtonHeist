import Foundation

import AccessibilitySnapshotModel
import TheScore

final class PublicIndexCounter {
    var value = 0
}

struct PublicSnapshotQuality: Encodable {
    let state: String
    let reasonCode: String?
    let observedElementCount: Int
    let renderedElementCount: Int
    let omittedElementCount: Int
    let visibleElementBudget: Int?
}

final class PublicInterfaceProjectionStats {
    let observedElementCount: Int
    private(set) var renderedElementCount = 0
    private(set) var truncatedScrollContainerCount = 0

    init(observedElementCount: Int) {
        self.observedElementCount = observedElementCount
    }

    func recordRenderedElement() {
        renderedElementCount += 1
    }

    func recordTruncatedScrollContainer() {
        truncatedScrollContainerCount += 1
    }

    func snapshotQuality(visibleElementBudget: Int) -> PublicSnapshotQuality {
        let omittedElementCount = max(0, observedElementCount - renderedElementCount)
        guard truncatedScrollContainerCount > 0 || omittedElementCount > 0 else {
            return PublicSnapshotQuality(
                state: "full",
                reasonCode: nil,
                observedElementCount: observedElementCount,
                renderedElementCount: renderedElementCount,
                omittedElementCount: 0,
                visibleElementBudget: nil
            )
        }

        return PublicSnapshotQuality(
            state: "truncated",
            reasonCode: "scroll-subtree-element-budget",
            observedElementCount: observedElementCount,
            renderedElementCount: renderedElementCount,
            omittedElementCount: omittedElementCount,
            visibleElementBudget: max(0, visibleElementBudget)
        )
    }
}

enum PublicTreeNode: Encodable {
    case element(PublicElement)
    case container(PublicContainer)

    private enum CodingKeys: String, CodingKey {
        case element
        case container
    }

    static func nodes(
        from tree: [AccessibilityHierarchy],
        detail: InterfaceDetail,
        counter: PublicIndexCounter?,
        visibleElementBudget: Int,
        projectionStats: PublicInterfaceProjectionStats,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> [PublicTreeNode] {
        var remainingElements: Int?
        return tree.enumerated().compactMap { index, node in
            Self.node(
                from: node,
                path: TreePath([index]),
                detail: detail,
                counter: counter,
                visibleElementBudget: visibleElementBudget,
                remainingElements: &remainingElements,
                projectionStats: projectionStats,
                elementAnnotations: elementAnnotations,
                containerAnnotations: containerAnnotations
            )
        }
    }

    static func node(
        from node: AccessibilityHierarchy,
        path: TreePath,
        detail: InterfaceDetail,
        counter: PublicIndexCounter?,
        visibleElementBudget: Int,
        remainingElements: inout Int?,
        projectionStats: PublicInterfaceProjectionStats,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> PublicTreeNode? {
        switch node {
        case .element(let element, _):
            let order = counter?.value
            counter?.value += 1
            if let remaining = remainingElements {
                guard remaining > 0 else { return nil }
                remainingElements = remaining - 1
            }
            projectionStats.recordRenderedElement()
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: elementAnnotations[path]
            )
            return .element(PublicElement(element: projected, detail: detail, order: order))
        case .container(let container, let children):
            let observedElementCount = children.reduce(0) { $0 + $1.pathIndexedElements().count }
            if let remaining = remainingElements, remaining <= 0 {
                counter?.value += observedElementCount
                return nil
            }

            let budgetCap = max(0, visibleElementBudget)
            let isScrollable = {
                if case .scrollable = container.type { return true }
                return false
            }()
            let shouldTruncate = isScrollable && observedElementCount > budgetCap
            let parentRemainingBefore = remainingElements
            var scrollRemainingElements: Int?
            var childNodes: [PublicTreeNode] = []

            if shouldTruncate {
                scrollRemainingElements = min(parentRemainingBefore ?? budgetCap, budgetCap)
                for (index, child) in children.enumerated() {
                    if let childNode = Self.node(
                        from: child,
                        path: path.appending(index),
                        detail: detail,
                        counter: counter,
                        visibleElementBudget: visibleElementBudget,
                        remainingElements: &scrollRemainingElements,
                        projectionStats: projectionStats,
                        elementAnnotations: elementAnnotations,
                        containerAnnotations: containerAnnotations
                    ) {
                        childNodes.append(childNode)
                    }
                }
            } else {
                for (index, child) in children.enumerated() {
                    if let childNode = Self.node(
                        from: child,
                        path: path.appending(index),
                        detail: detail,
                        counter: counter,
                        visibleElementBudget: visibleElementBudget,
                        remainingElements: &remainingElements,
                        projectionStats: projectionStats,
                        elementAnnotations: elementAnnotations,
                        containerAnnotations: containerAnnotations
                    ) {
                        childNodes.append(childNode)
                    }
                }
            }

            let truncation: PublicSubtreeTruncation?
            if shouldTruncate {
                let effectiveBudget = min(parentRemainingBefore ?? budgetCap, budgetCap)
                let renderedElementCount = max(0, effectiveBudget - (scrollRemainingElements ?? 0))
                if let parentRemainingBefore {
                    remainingElements = max(0, parentRemainingBefore - renderedElementCount)
                }
                let omittedElementCount = max(0, observedElementCount - renderedElementCount)
                if omittedElementCount > 0 {
                    projectionStats.recordTruncatedScrollContainer()
                    truncation = PublicSubtreeTruncation(
                        observedElementCount: observedElementCount,
                        renderedElementCount: renderedElementCount,
                        omittedElementCount: omittedElementCount,
                        visibleElementBudget: budgetCap
                    )
                } else {
                    truncation = nil
                }
            } else {
                truncation = nil
            }

            return .container(PublicContainer(
                container: container,
                annotation: containerAnnotations[path],
                detail: detail,
                observedElementCount: observedElementCount,
                truncation: truncation,
                children: childNodes
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let element):
            try container.encode(element, forKey: .element)
        case .container(let node):
            try container.encode(node, forKey: .container)
        }
    }

    var elementCount: Int {
        switch self {
        case .element:
            return 1
        case .container(let container):
            return container.children.reduce(0) { $0 + $1.elementCount }
        }
    }
}
