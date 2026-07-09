import Foundation

/// Direction for scroll actions
public enum ScrollDirection: String, Codable, Sendable, CaseIterable, Equatable {
    case up, down, left, right
}

public enum ScrollContainerSelection: Sendable, Equatable, CustomStringConvertible {
    case visibleContainer
    case element(ElementTarget)
    case container(ContainerName)

    public var description: String {
        switch self {
        case .visibleContainer:
            return "visibleContainer"
        case .element(let target):
            return target.description
        case .container(let containerName):
            return ScoreDescription.call("container", [
                "containerName=\(ScoreDescription.quoted(containerName.rawValue))",
            ])
        }
    }
}

/// Target for one-page scroll command.
public struct ScrollTarget: Sendable, Equatable {
    /// Scroll subject to move.
    public let selection: ScrollContainerSelection
    /// Scroll direction
    public let direction: ScrollDirection

    public init(
        selection: ScrollContainerSelection = .visibleContainer,
        direction: ScrollDirection = .down
    ) {
        self.selection = selection
        self.direction = direction
    }

    public init(
        elementTarget: ElementTarget,
        direction: ScrollDirection = .down
    ) {
        self.init(selection: .element(elementTarget), direction: direction)
    }

    private var elementTarget: ElementTarget? {
        guard case .element(let target) = selection else { return nil }
        return target
    }

    private var containerName: ContainerName? {
        guard case .container(let containerName) = selection else { return nil }
        return containerName
    }

    private var selectionDescription: String? {
        switch selection {
        case .visibleContainer:
            return nil
        case .element(let target):
            return target.description
        case .container(let containerName):
            return ScrollContainerSelection.container(containerName).description
        }
    }
}

extension ScrollTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scroll", [
            selectionDescription,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

extension ScrollTarget: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case direction
        case containerName
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownScrollPayloadKeys(
            from: decoder,
            commandFields: [CodingKeys.direction.stringValue],
            allowsContainerNameKey: true,
            typeName: "scroll target"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let containerName = try container.decodeIfPresent(ContainerName.self, forKey: .containerName)
        let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        if containerName != nil, elementTarget != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .containerName,
                in: container,
                debugDescription: "ScrollTarget requires either containerName or element target fields, not both"
            )
        }
        switch elementTarget {
        case .some(let elementTarget):
            self.selection = .element(elementTarget)
        case nil:
            self.selection = containerName.map(ScrollContainerSelection.container) ?? .visibleContainer
        }
        self.direction = try container.decode(ScrollDirection.self, forKey: .direction)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(containerName, forKey: .containerName)
        try container.encode(direction, forKey: .direction)
    }
}

/// Target for one-shot scroll-to-visible.
/// The element must be present in semantic state with scroll membership.
/// Scans the owning scroll container to reveal the element; it is an explicit viewport command,
/// not setup for ordinary semantic actions.
public struct ScrollToVisibleTarget: Sendable, Equatable {
    /// Element to scroll into view. Must be a known element with scroll membership.
    public let elementTarget: ElementTarget
    public init(elementTarget: ElementTarget) {
        self.elementTarget = elementTarget
    }
}

extension ScrollToVisibleTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToVisible", [
            elementTarget.description,
        ].compactMap { $0 })
    }
}

extension ScrollToVisibleTarget: Codable {
    public init(from decoder: Decoder) throws {
        try rejectUnknownScrollPayloadKeys(from: decoder, typeName: "scroll_to_visible target")
        guard let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "ScrollToVisibleTarget requires an element target"
                )
            )
        }
        self.elementTarget = elementTarget
    }

    public func encode(to encoder: Encoder) throws {
        try elementTarget.encode(to: encoder)
    }
}

/// Edge for scroll-to-edge commands
public enum ScrollEdge: String, Codable, Sendable, CaseIterable, Equatable {
    case top, bottom, left, right
}

/// Target for scroll-to-edge command
public struct ScrollToEdgeTarget: Sendable, Equatable {
    /// Scroll subject to move.
    public let selection: ScrollContainerSelection
    /// Which edge to scroll to
    public let edge: ScrollEdge

    public init(
        selection: ScrollContainerSelection = .visibleContainer,
        edge: ScrollEdge = .top
    ) {
        self.selection = selection
        self.edge = edge
    }

    public init(
        elementTarget: ElementTarget,
        edge: ScrollEdge = .top
    ) {
        self.init(selection: .element(elementTarget), edge: edge)
    }

    private var elementTarget: ElementTarget? {
        guard case .element(let target) = selection else { return nil }
        return target
    }

    private var containerName: ContainerName? {
        guard case .container(let containerName) = selection else { return nil }
        return containerName
    }

    private var selectionDescription: String? {
        switch selection {
        case .visibleContainer:
            return nil
        case .element(let target):
            return target.description
        case .container(let containerName):
            return ScrollContainerSelection.container(containerName).description
        }
    }
}

extension ScrollToEdgeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToEdge", [
            selectionDescription,
            ScoreDescription.valueField("edge", edge),
        ].compactMap { $0 })
    }
}

extension ScrollToEdgeTarget: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case edge
        case containerName
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownScrollPayloadKeys(
            from: decoder,
            commandFields: [CodingKeys.edge.stringValue],
            allowsContainerNameKey: true,
            typeName: "scroll_to_edge target"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let containerName = try container.decodeIfPresent(ContainerName.self, forKey: .containerName)
        let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        if containerName != nil, elementTarget != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .containerName,
                in: container,
                debugDescription: "ScrollToEdgeTarget requires either containerName or element target fields, not both"
            )
        }
        switch elementTarget {
        case .some(let elementTarget):
            self.selection = .element(elementTarget)
        case nil:
            self.selection = containerName.map(ScrollContainerSelection.container) ?? .visibleContainer
        }
        self.edge = try container.decode(ScrollEdge.self, forKey: .edge)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(containerName, forKey: .containerName)
        try container.encode(edge, forKey: .edge)
    }
}

private func rejectUnknownScrollPayloadKeys(
    from decoder: Decoder,
    commandFields: [String] = [],
    allowsContainerNameKey: Bool = false,
    typeName: String
) throws {
    let containerNameKeys = allowsContainerNameKey ? ["containerName"] : []
    let allowed = Set(ElementTarget.inlineFieldNames + commandFields + containerNameKeys)
    try decoder.rejectUnknownKeys(allowed: allowed, typeName: typeName)
}
