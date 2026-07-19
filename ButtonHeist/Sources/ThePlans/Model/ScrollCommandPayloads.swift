import Foundation

/// Direction for scroll actions
public enum ScrollDirection: String, Codable, Sendable, CaseIterable, Equatable {
    case up, down, left, right
}

public enum ScrollContainerSelection: Sendable, Equatable, CustomStringConvertible {
    case visibleContainer
    case element(AccessibilityTarget)
    case container(ContainerName)

    public var description: String {
        switch self {
        case .visibleContainer:
            return "visibleContainer"
        case .element(let target):
            return target.description
        case .container(let containerName):
            return CanonicalValueDescription.call("container", [
                "containerName=\(CanonicalValueDescription.quoted(containerName.rawValue))",
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
        target: AccessibilityTarget,
        direction: ScrollDirection = .down
    ) {
        self.init(selection: .element(target), direction: direction)
    }

    private var target: AccessibilityTarget? {
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
        CanonicalValueDescription.call("scroll", [
            selectionDescription,
            CanonicalValueDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

extension ScrollTarget: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case direction
        case containerName
        case target
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "scroll target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let containerName = try container.decodeIfPresent(ContainerName.self, forKey: .containerName)
        let target = try container.decodeIfPresent(AccessibilityTarget.self, forKey: .target)
        if containerName != nil, target != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .containerName,
                in: container,
                debugDescription: "ScrollTarget requires either containerName or element target fields, not both"
            )
        }
        switch target {
        case .some(let target):
            self.selection = .element(target)
        case nil:
            self.selection = containerName.map(ScrollContainerSelection.container) ?? .visibleContainer
        }
        self.direction = try container.decode(ScrollDirection.self, forKey: .direction)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(target, forKey: .target)
        try container.encodeIfPresent(containerName, forKey: .containerName)
        try container.encode(direction, forKey: .direction)
    }
}

/// Target for one-shot scroll-to-visible.
/// The element must be present in semantic state with scroll membership.
/// Scans the owning scroll container to reveal the element; it is an explicit scroll command,
/// not setup for ordinary semantic actions.
public struct ScrollToVisibleTarget: Sendable, Equatable {
    /// Element to scroll into view. Must be a known element with scroll membership.
    public let target: AccessibilityTarget
    public init(target: AccessibilityTarget) {
        self.target = target
    }
}

extension ScrollToVisibleTarget: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("scrollToVisible", [
            target.description,
        ].compactMap { $0 })
    }
}

extension ScrollToVisibleTarget: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case target
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "scroll_to_visible target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(AccessibilityTarget.self, forKey: .target)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
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
        target: AccessibilityTarget,
        edge: ScrollEdge = .top
    ) {
        self.init(selection: .element(target), edge: edge)
    }

    private var target: AccessibilityTarget? {
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
        CanonicalValueDescription.call("scrollToEdge", [
            selectionDescription,
            CanonicalValueDescription.valueField("edge", edge),
        ].compactMap { $0 })
    }
}

extension ScrollToEdgeTarget: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case edge
        case containerName
        case target
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "scroll_to_edge target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let containerName = try container.decodeIfPresent(ContainerName.self, forKey: .containerName)
        let target = try container.decodeIfPresent(AccessibilityTarget.self, forKey: .target)
        if containerName != nil, target != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .containerName,
                in: container,
                debugDescription: "ScrollToEdgeTarget requires either containerName or element target fields, not both"
            )
        }
        switch target {
        case .some(let target):
            self.selection = .element(target)
        case nil:
            self.selection = containerName.map(ScrollContainerSelection.container) ?? .visibleContainer
        }
        self.edge = try container.decode(ScrollEdge.self, forKey: .edge)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(target, forKey: .target)
        try container.encodeIfPresent(containerName, forKey: .containerName)
        try container.encode(edge, forKey: .edge)
    }
}
