import ThePlans
import Foundation
import AccessibilitySnapshotModel

extension Interface {
    private enum CodingKeys: String, CodingKey {
        case timestamp
        case tree
        case annotations
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        tree = try container
            .decode([InterfaceTreeWireNode].self, forKey: .tree)
            .map { $0.hierarchy }
        annotations = try container.decode(InterfaceAnnotations.self, forKey: .annotations)
        diagnostics = try container.decodeIfPresent(InterfaceDiagnostics.self, forKey: .diagnostics)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(tree.map(InterfaceTreeWireNode.init), forKey: .tree)
        try container.encode(annotations, forKey: .annotations)
        try container.encodeIfPresent(diagnostics, forKey: .diagnostics)
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
        case type
        case frame
        case isModalBoundary
        case customActions
        case children
    }

    init(container: AccessibilityContainer, children: [InterfaceTreeWireNode]) {
        self.container = container
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let codingContainer = try decoder.container(keyedBy: CodingKeys.self)
        let type = try codingContainer.decode(AccessibilityContainer.ContainerType.self, forKey: .type)
        let frame = try codingContainer.decode(InterfaceRectWirePayload.self, forKey: .frame).rect
        let isModalBoundary = try codingContainer.decode(Bool.self, forKey: .isModalBoundary)
        let customActions = try codingContainer.decodeIfPresent(
            [AccessibilityElement.CustomAction].self,
            forKey: .customActions
        ) ?? []
        children = try codingContainer.decode([InterfaceTreeWireNode].self, forKey: .children)
        container = AccessibilityContainer(
            type: type,
            frame: frame,
            isModalBoundary: isModalBoundary,
            customActions: customActions
        )
    }

    func encode(to encoder: Encoder) throws {
        // The public wire shape intentionally flattens parser fields beside
        // Button Heist hierarchy metadata instead of exposing Swift enum wrappers.
        var codingContainer = encoder.container(keyedBy: CodingKeys.self)
        try codingContainer.encode(container.type, forKey: .type)
        try codingContainer.encode(InterfaceRectWirePayload(container.frame), forKey: .frame)
        try codingContainer.encode(container.isModalBoundary, forKey: .isModalBoundary)
        try codingContainer.encode(container.customActions, forKey: .customActions)
        try codingContainer.encode(children, forKey: .children)
    }
}

private struct InterfaceRectWirePayload: Codable {
    let rect: AccessibilityRect

    private enum CodingKeys: String, CodingKey {
        case origin
        case size
    }

    init(_ rect: AccessibilityRect) {
        self.rect = rect
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.origin),
           container.contains(.size) {
            rect = AccessibilityRect(
                origin: try container.decode(InterfacePointWirePayload.self, forKey: .origin).point,
                size: try container.decode(InterfaceSizeWirePayload.self, forKey: .size).size
            )
        } else {
            rect = try AccessibilityRect(from: decoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(InterfacePointWirePayload(rect.origin), forKey: .origin)
        try container.encode(InterfaceSizeWirePayload(rect.size), forKey: .size)
    }
}

private struct InterfacePointWirePayload: Codable {
    let point: AccessibilityPoint

    private enum CodingKeys: String, CodingKey {
        case x
        case y
    }

    init(_ point: AccessibilityPoint) {
        self.point = point
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.x),
           container.contains(.y) {
            point = AccessibilityPoint(
                x: try container.decode(Double.self, forKey: .x),
                y: try container.decode(Double.self, forKey: .y)
            )
        } else {
            point = try AccessibilityPoint(from: decoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(point.x, forKey: .x)
        try container.encode(point.y, forKey: .y)
    }
}

private struct InterfaceSizeWirePayload: Codable {
    let size: AccessibilitySize

    private enum CodingKeys: String, CodingKey {
        case width
        case height
    }

    init(_ size: AccessibilitySize) {
        self.size = size
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.width),
           container.contains(.height) {
            size = AccessibilitySize(
                width: try container.decode(Double.self, forKey: .width),
                height: try container.decode(Double.self, forKey: .height)
            )
        } else {
            size = try AccessibilitySize(from: decoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(size.width, forKey: .width)
        try container.encode(size.height, forKey: .height)
    }
}
