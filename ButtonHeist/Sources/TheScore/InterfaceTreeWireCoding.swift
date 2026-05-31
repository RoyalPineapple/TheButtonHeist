import Foundation
import AccessibilitySnapshotModel

extension Interface {
    private enum CodingKeys: String, CodingKey {
        case timestamp
        case tree
        case annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        tree = try container
            .decode([InterfaceTreeWireNode].self, forKey: .tree)
            .map { $0.hierarchy }
        annotations = try container.decode(InterfaceAnnotations.self, forKey: .annotations)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(tree.map(InterfaceTreeWireNode.init), forKey: .tree)
        try container.encode(annotations, forKey: .annotations)
    }
}

private enum InterfaceTreeWireNode: Codable {
    case element(AccessibilityElement, traversalIndex: Int)
    case container(AccessibilityContainer, children: [InterfaceTreeWireNode])

    private enum CodingKeys: String, CodingKey {
        case element
        case container
    }

    init(_ hierarchy: AccessibilityHierarchy) {
        switch hierarchy {
        case .element(let element, let traversalIndex):
            self = .element(element, traversalIndex: traversalIndex)
        case .container(let container, let children):
            self = .container(container, children: children.map(Self.init))
        }
    }

    var hierarchy: AccessibilityHierarchy {
        switch self {
        case .element(let element, let traversalIndex):
            return .element(element, traversalIndex: traversalIndex)
        case .container(let container, let children):
            return .container(container, children: children.map { $0.hierarchy })
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (container.contains(.element), container.contains(.container)) {
        case (true, false):
            let payload = try container.decode(InterfaceElementWirePayload.self, forKey: .element)
            self = .element(payload.element, traversalIndex: payload.traversalIndex)
        case (false, true):
            let payload = try container.decode(InterfaceContainerWirePayload.self, forKey: .container)
            self = .container(payload.container, children: payload.children)
        case (true, true):
            throw DecodingError.dataCorruptedError(
                forKey: .element,
                in: container,
                debugDescription: "Interface tree node must contain exactly one of element or container"
            )
        case (false, false):
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Interface tree node requires element or container"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let element, let traversalIndex):
            try container.encode(
                InterfaceElementWirePayload(element: element, traversalIndex: traversalIndex),
                forKey: .element
            )
        case .container(let node, let children):
            try container.encode(
                InterfaceContainerWirePayload(container: node, children: children),
                forKey: .container
            )
        }
    }
}

private struct InterfaceElementWirePayload: Codable {
    let element: AccessibilityElement
    let traversalIndex: Int

    private enum CodingKeys: String, CodingKey {
        case traversalIndex
    }

    init(element: AccessibilityElement, traversalIndex: Int) {
        self.element = element
        self.traversalIndex = traversalIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        traversalIndex = try container.decode(Int.self, forKey: .traversalIndex)
        element = try AccessibilityElement(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        // The public wire shape intentionally flattens parser fields beside
        // Button Heist traversal metadata instead of exposing Swift enum wrappers.
        try element.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(traversalIndex, forKey: .traversalIndex)
    }
}

private struct InterfaceContainerWirePayload: Codable {
    let container: AccessibilityContainer
    let children: [InterfaceTreeWireNode]

    private enum CodingKeys: String, CodingKey {
        case children
    }

    init(container: AccessibilityContainer, children: [InterfaceTreeWireNode]) {
        self.container = container
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let codingContainer = try decoder.container(keyedBy: CodingKeys.self)
        children = try codingContainer.decode([InterfaceTreeWireNode].self, forKey: .children)
        container = try AccessibilityContainer(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        // The public wire shape intentionally flattens parser fields beside
        // Button Heist hierarchy metadata instead of exposing Swift enum wrappers.
        try container.encode(to: encoder)
        var codingContainer = encoder.container(keyedBy: CodingKeys.self)
        try codingContainer.encode(children, forKey: .children)
    }
}
