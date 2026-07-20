import ThePlans
import Foundation
import AccessibilitySnapshotModel

extension Interface {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case timestamp
        case tree
        case annotations
        case diagnostics
        case screenActions
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)
        let tree = try container
            .decode([InterfaceTreeWireNode].self, forKey: .tree)
            .map { $0.hierarchy }
        let annotations = try container.decode(InterfaceAnnotations.self, forKey: .annotations)
        let diagnostics = try container.decodeIfPresent(InterfaceDiagnostics.self, forKey: .diagnostics)
        let screenActions = try container.decodeIfPresent([ScreenAction].self, forKey: .screenActions) ?? []
        do {
            try self.init(
                timestamp: timestamp,
                tree: tree,
                annotations: annotations,
                diagnostics: diagnostics,
                screenActions: screenActions,
                traceIdentities: .empty
            )
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid Interface graph: \(error)",
                underlyingError: error
            ))
        }

    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(tree.map(InterfaceTreeWireNode.init), forKey: .tree)
        try container.encode(annotations, forKey: .annotations)
        try container.encodeIfPresent(diagnostics, forKey: .diagnostics)
        if !screenActions.isEmpty {
            try container.encode(screenActions, forKey: .screenActions)
        }
    }
}

private enum InterfaceTreeWireNode: Codable {
    case element(AccessibilityElement, traversalIndex: Int)
    case container(AccessibilityContainer, children: [InterfaceTreeWireNode])

    private enum CodingKeys: String, CodingKey, CaseIterable {
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
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface tree node")
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case description
        case label
        case value
        case traits
        case identifier
        case hint
        case userInputLabels
        case shape
        case activationPoint
        case usesDefaultActivationPoint
        case customActions
        case customContent
        case customRotors
        case accessibilityLanguage
        case respondsToUserInteraction
        case visibility
        case traversalIndex
    }

    init(element: AccessibilityElement, traversalIndex: Int) {
        self.element = element
        self.traversalIndex = traversalIndex
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface element")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try InterfaceShapeWireValidation.validate(
            from: container.superDecoder(forKey: .shape)
        )
        try rejectUnknownObjectFields(
            in: container.nestedUnkeyedContainer(forKey: .customActions),
            allowed: ["name"],
            typeName: "interface custom action"
        )
        try rejectUnknownObjectFields(
            in: container.nestedUnkeyedContainer(forKey: .customContent),
            allowed: ["label", "value", "isImportant"],
            typeName: "interface custom content"
        )
        try InterfaceCustomRotorWireValidation.validate(
            container.nestedUnkeyedContainer(forKey: .customRotors)
        )
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case identifier
        case scrollableContentSize
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
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface container")
        let codingContainer = try decoder.container(keyedBy: CodingKeys.self)
        try InterfaceContainerTypeWireValidation.validate(
            from: codingContainer.superDecoder(forKey: .type)
        )
        try rejectUnknownObjectFields(
            in: codingContainer.nestedUnkeyedContainer(forKey: .customActions),
            allowed: ["name"],
            typeName: "interface custom action"
        )
        let type = try codingContainer.decode(AccessibilityContainer.ContainerType.self, forKey: .type)
        let identifier = try codingContainer.decodeIfPresent(String.self, forKey: .identifier)
        let scrollableContentSize = try codingContainer.decodeIfPresent(
            InterfaceSizeWirePayload.self,
            forKey: .scrollableContentSize
        )?.size
        let frame = try codingContainer.decode(InterfaceRectWirePayload.self, forKey: .frame).rect
        let isModalBoundary = try codingContainer.decode(Bool.self, forKey: .isModalBoundary)
        let customActions = try codingContainer.decode(
            [AccessibilityElement.CustomAction].self,
            forKey: .customActions
        )
        children = try codingContainer.decode([InterfaceTreeWireNode].self, forKey: .children)
        container = AccessibilityContainer(
            type: type,
            identifier: identifier,
            scrollableContentSize: scrollableContentSize,
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
        try codingContainer.encodeIfPresent(container.identifier, forKey: .identifier)
        try codingContainer.encodeIfPresent(
            container.scrollableContentSize.map(InterfaceSizeWirePayload.init),
            forKey: .scrollableContentSize
        )
        try codingContainer.encode(InterfaceRectWirePayload(container.frame), forKey: .frame)
        try codingContainer.encode(container.isModalBoundary, forKey: .isModalBoundary)
        try codingContainer.encode(container.customActions, forKey: .customActions)
        try codingContainer.encode(children, forKey: .children)
    }
}

private struct InterfaceRectWirePayload: Codable {
    let rect: AccessibilityRect

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case origin
        case size
    }

    init(_ rect: AccessibilityRect) {
        self.rect = rect
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface rect")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rect = AccessibilityRect(
            origin: try container.decode(InterfacePointWirePayload.self, forKey: .origin).point,
            size: try container.decode(InterfaceSizeWirePayload.self, forKey: .size).size
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(InterfacePointWirePayload(rect.origin), forKey: .origin)
        try container.encode(InterfaceSizeWirePayload(rect.size), forKey: .size)
    }
}

private struct InterfacePointWirePayload: Codable {
    let point: AccessibilityPoint

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x
        case y
    }

    init(_ point: AccessibilityPoint) {
        self.point = point
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface point")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        point = AccessibilityPoint(
            x: try container.decode(Double.self, forKey: .x),
            y: try container.decode(Double.self, forKey: .y)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(point.x, forKey: .x)
        try container.encode(point.y, forKey: .y)
    }
}

private struct InterfaceSizeWirePayload: Codable {
    let size: AccessibilitySize

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case width
        case height
    }

    init(_ size: AccessibilitySize) {
        self.size = size
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface size")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = AccessibilitySize(
            width: try container.decode(Double.self, forKey: .width),
            height: try container.decode(Double.self, forKey: .height)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(size.width, forKey: .width)
        try container.encode(size.height, forKey: .height)
    }
}

private enum InterfaceShapeWireValidation {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case frame
        case pathElements
    }

    private enum ShapeType: String, Decodable {
        case frame
        case path
    }

    private enum PathCodingKeys: String, CodingKey, CaseIterable {
        case move
        case line
        case quadCurve
        case curve
        case closeSubpath
    }

    static func validate(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface shape")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ShapeType.self, forKey: .type) {
        case .frame:
            try container.rejectIncompatibleFields(
                allowing: [.type, .frame],
                typeName: "frame interface shape"
            )
        case .path:
            try container.rejectIncompatibleFields(
                allowing: [.type, .pathElements],
                typeName: "path interface shape"
            )
            var elements = try container.nestedUnkeyedContainer(forKey: .pathElements)
            while !elements.isAtEnd {
                try validatePathElement(from: elements.superDecoder())
            }
        }
    }

    private static func validatePathElement(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: PathCodingKeys.self, typeName: "interface path element")
        let container = try decoder.container(keyedBy: PathCodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Interface path element must contain exactly one path operation"
            ))
        }
        let allowedPayloadKeys: Set<String> = switch key {
        case .move, .line:
            ["to"]
        case .quadCurve:
            ["to", "control"]
        case .curve:
            ["to", "control1", "control2"]
        case .closeSubpath:
            []
        }
        try container
            .superDecoder(forKey: key)
            .rejectUnknownKeys(allowed: allowedPayloadKeys, typeName: "interface path operation")
    }
}

private enum InterfaceCustomRotorWireValidation {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case resultMarkers
        case limit
    }

    private enum MarkerCodingKeys: String, CodingKey, CaseIterable {
        case elementDescription
        case rangeDescription
        case shape
    }

    private enum LimitCodingKeys: String, CodingKey, CaseIterable {
        case none
        case underMaxCount
        case greaterThanMaxCount
    }

    static func validate(_ values: UnkeyedDecodingContainer) throws {
        var values = values
        while !values.isAtEnd {
            let decoder = try values.superDecoder()
            try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface custom rotor")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var markers = try container.nestedUnkeyedContainer(forKey: .resultMarkers)
            while !markers.isAtEnd {
                let markerDecoder = try markers.superDecoder()
                try markerDecoder.rejectUnknownKeys(
                    allowed: MarkerCodingKeys.self,
                    typeName: "interface custom rotor result"
                )
                let marker = try markerDecoder.container(keyedBy: MarkerCodingKeys.self)
                if marker.contains(.shape) {
                    try InterfaceShapeWireValidation.validate(
                        from: marker.superDecoder(forKey: .shape)
                    )
                }
            }
            try validateLimit(from: container.superDecoder(forKey: .limit))
        }
    }

    private static func validateLimit(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: LimitCodingKeys.self, typeName: "interface rotor result limit")
        let container = try decoder.container(keyedBy: LimitCodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Interface rotor result limit must contain exactly one case"
            ))
        }
        let allowedPayloadKeys: Set<String> = key == .underMaxCount ? ["_0"] : []
        try container
            .superDecoder(forKey: key)
            .rejectUnknownKeys(allowed: allowedPayloadKeys, typeName: "interface rotor result limit payload")
    }
}

private enum InterfaceContainerTypeWireValidation {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case none
        case semanticGroup
        case list
        case landmark
        case dataTable
        case tabBar
        case series
        case scrollable
    }

    private enum DataTableCodingKeys: String, CodingKey, CaseIterable {
        case rowCount
        case columnCount
        case cells
    }

    static func validate(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "interface container type")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Interface container type must contain exactly one case"
            ))
        }
        let allowedPayloadKeys: Set<String> = switch key {
        case .none, .list, .landmark, .tabBar, .series:
            []
        case .semanticGroup:
            ["label", "value"]
        case .dataTable:
            Set(DataTableCodingKeys.allCases.map(\.stringValue))
        case .scrollable:
            ["contentSize"]
        }
        let payloadDecoder = try container.superDecoder(forKey: key)
        try payloadDecoder.rejectUnknownKeys(
            allowed: allowedPayloadKeys,
            typeName: "interface container type payload"
        )
        guard key == .dataTable else { return }
        let payload = try payloadDecoder.container(keyedBy: DataTableCodingKeys.self)
        try rejectUnknownObjectFields(
            in: payload.nestedUnkeyedContainer(forKey: .cells),
            allowed: [
                "row", "column", "rowSpan", "columnSpan", "isFirstInRow",
                "rowHeaderChildIndices", "columnHeaderChildIndices",
            ],
            typeName: "interface data table cell",
            allowsNull: true
        )
    }
}

private func rejectUnknownObjectFields(
    in values: UnkeyedDecodingContainer,
    allowed: Set<String>,
    typeName: String,
    allowsNull: Bool = false
) throws {
    var values = values
    while !values.isAtEnd {
        if allowsNull, try values.decodeNil() { continue }
        try values.superDecoder().rejectUnknownKeys(allowed: allowed, typeName: typeName)
    }
}
