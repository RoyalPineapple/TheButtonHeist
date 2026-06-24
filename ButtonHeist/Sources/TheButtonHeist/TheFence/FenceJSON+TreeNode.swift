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
    let totalNodeBudget: Int?
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

    func snapshotQuality(
        visibleElementBudget: Int,
        totalNodeBudget: Int,
        totalNodeBudgetHit: Bool
    ) -> PublicSnapshotQuality {
        let omittedElementCount = max(0, observedElementCount - renderedElementCount)
        guard truncatedScrollContainerCount > 0 || omittedElementCount > 0 else {
            return PublicSnapshotQuality(
                state: "full",
                reasonCode: nil,
                observedElementCount: observedElementCount,
                renderedElementCount: renderedElementCount,
                omittedElementCount: 0,
                visibleElementBudget: nil,
                totalNodeBudget: nil
            )
        }

        return PublicSnapshotQuality(
            state: "truncated",
            reasonCode: totalNodeBudgetHit ? "total-node-budget" : "scroll-subtree-element-budget",
            observedElementCount: observedElementCount,
            renderedElementCount: renderedElementCount,
            omittedElementCount: omittedElementCount,
            visibleElementBudget: truncatedScrollContainerCount > 0 ? max(0, visibleElementBudget) : nil,
            totalNodeBudget: totalNodeBudgetHit ? max(0, totalNodeBudget) : nil
        )
    }
}

final class PublicElementBudgetTracker {
    let budget: Int
    private(set) var remaining: Int
    private(set) var wasLimited = false

    init(budget: Int) {
        let boundedBudget = max(0, budget)
        self.budget = boundedBudget
        self.remaining = boundedBudget
    }

    var hasCapacity: Bool {
        remaining > 0
    }

    func consumeElement() -> Bool {
        guard remaining > 0 else {
            wasLimited = true
            return false
        }
        remaining -= 1
        return true
    }

    func recordLimitHit() {
        wasLimited = true
    }
}

struct PublicTreeProjectionContext {
    let detail: InterfaceDetail
    let counter: PublicIndexCounter?
    let visibleElementBudget: Int
    let totalNodeBudget: PublicElementBudgetTracker
    let projectionStats: PublicInterfaceProjectionStats
    let elementAnnotations: [TreePath: InterfaceElementAnnotation]
    let containerAnnotations: [TreePath: InterfaceContainerAnnotation]
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
        totalNodeBudget: PublicElementBudgetTracker,
        projectionStats: PublicInterfaceProjectionStats,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> [PublicTreeNode] {
        let context = PublicTreeProjectionContext(
            detail: detail,
            counter: counter,
            visibleElementBudget: visibleElementBudget,
            totalNodeBudget: totalNodeBudget,
            projectionStats: projectionStats,
            elementAnnotations: elementAnnotations,
            containerAnnotations: containerAnnotations
        )
        var remainingElements: Int?
        return tree.enumerated().compactMap { index, node in
            Self.node(
                from: node,
                path: TreePath([index]),
                context: context,
                remainingElements: &remainingElements,
            )
        }
    }

    static func node(
        from node: AccessibilityHierarchy,
        path: TreePath,
        context: PublicTreeProjectionContext,
        remainingElements: inout Int?
    ) -> PublicTreeNode? {
        switch node {
        case .element(let element, _):
            let order = context.counter?.value
            context.counter?.value += 1
            if let remaining = remainingElements {
                guard remaining > 0 else { return nil }
            }
            guard context.totalNodeBudget.consumeElement() else { return nil }
            if let remaining = remainingElements {
                remainingElements = remaining - 1
            }
            context.projectionStats.recordRenderedElement()
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: context.elementAnnotations[path]
            )
            return .element(PublicElement(element: projected, detail: context.detail, order: order))
        case .container(let container, let children):
            let observedElementCount = children.reduce(0) { $0 + $1.pathIndexedElements().count }
            if let remaining = remainingElements, remaining <= 0 {
                context.counter?.value += observedElementCount
                return nil
            }
            if !context.totalNodeBudget.hasCapacity, observedElementCount > 0 {
                context.counter?.value += observedElementCount
                context.totalNodeBudget.recordLimitHit()
                return nil
            }

            let budgetCap = max(0, context.visibleElementBudget)
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
                        context: context,
                        remainingElements: &scrollRemainingElements,
                    ) {
                        childNodes.append(childNode)
                    }
                }
            } else {
                for (index, child) in children.enumerated() {
                    if let childNode = Self.node(
                        from: child,
                        path: path.appending(index),
                        context: context,
                        remainingElements: &remainingElements,
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
                let scrollBudgetHit = (scrollRemainingElements ?? 0) <= 0
                if scrollBudgetHit, omittedElementCount > 0 {
                    context.projectionStats.recordTruncatedScrollContainer()
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
                annotation: context.containerAnnotations[path],
                detail: context.detail,
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
