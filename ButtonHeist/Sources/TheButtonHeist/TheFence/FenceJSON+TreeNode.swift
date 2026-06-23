import Foundation

import AccessibilitySnapshotModel
import TheScore

final class PublicIndexCounter {
    var value = 0
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
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> [PublicTreeNode] {
        tree.enumerated().map { index, node in
            Self.node(
                from: node,
                path: TreePath([index]),
                detail: detail,
                counter: counter,
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
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> PublicTreeNode {
        switch node {
        case .element(let element, _):
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: elementAnnotations[path]
            )
            let order = counter?.value
            counter?.value += 1
            return .element(PublicElement(element: projected, detail: detail, order: order))
        case .container(let container, let children):
            let childNodes = children.enumerated().map { index, child in
                Self.node(
                    from: child,
                    path: path.appending(index),
                    detail: detail,
                    counter: counter,
                    elementAnnotations: elementAnnotations,
                    containerAnnotations: containerAnnotations
                )
            }
            return .container(PublicContainer(
                container: container,
                annotation: containerAnnotations[path],
                detail: detail,
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
