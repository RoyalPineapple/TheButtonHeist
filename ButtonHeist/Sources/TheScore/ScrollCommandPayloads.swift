import Foundation

/// Direction for scroll actions
public enum ScrollDirection: String, Codable, Sendable, CaseIterable {
    case up, down, left, right, next, previous
}

/// Target for container-moving scroll commands.
public struct ScrollContainerTarget: Codable, Sendable, Equatable {
    /// Stable container id returned by get_interface.
    public let stableId: HeistContainer?
    /// Capture-local container ref, for clients that retain a local capture handle.
    public let captureLocalRef: String?

    public init(stableId: HeistContainer? = nil, captureLocalRef: String? = nil) {
        self.stableId = stableId
        self.captureLocalRef = captureLocalRef
    }
}

extension ScrollContainerTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("container", [
            ScoreDescription.stringField("stableId", stableId),
            ScoreDescription.stringField("captureLocalRef", captureLocalRef),
        ].compactMap { $0 })
    }
}

public enum ScrollContainerSelection: Sendable, Equatable, CustomStringConvertible {
    case visibleContainer
    case container(ScrollContainerTarget)
    case element(ElementTarget)

    public var description: String {
        switch self {
        case .visibleContainer:
            return "visibleContainer"
        case .container(let target):
            return target.description
        case .element(let target):
            return target.description
        }
    }
}

/// Target for one-page scroll command.
public struct ScrollTarget: Sendable {
    /// Explicit scroll container to move.
    public let containerTarget: ScrollContainerTarget?
    /// Compatibility: element whose owning scroll container should move.
    public let elementTarget: ElementTarget?
    /// Scroll direction
    public let direction: ScrollDirection

    public init(
        elementTarget: ElementTarget? = nil,
        containerTarget: ScrollContainerTarget? = nil,
        direction: ScrollDirection = .down
    ) {
        self.elementTarget = elementTarget
        self.containerTarget = containerTarget
        self.direction = direction
    }

    public var containerSelection: ScrollContainerSelection {
        if let containerTarget {
            return .container(containerTarget)
        }
        if let elementTarget {
            return .element(elementTarget)
        }
        return .visibleContainer
    }
}

extension ScrollTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scroll", [
            containerTarget?.description,
            elementTarget?.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

extension ScrollTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case direction
        case container
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.containerTarget = try container.decodeIfPresent(ScrollContainerTarget.self, forKey: .container)
        self.elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        self.direction = try container.decodeIfPresent(ScrollDirection.self, forKey: .direction) ?? .down
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(containerTarget, forKey: .container)
        try container.encode(direction, forKey: .direction)
    }
}

/// Direction for scroll search
public enum ScrollSearchDirection: String, Codable, Sendable, CaseIterable {
    case down, up, left, right
}

/// Target for one-shot scroll-to-visible.
/// The element must be known (in the registry with a content-space position).
/// Jumps directly to the element's position — no iterative search.
public struct ScrollToVisibleTarget: Sendable {
    /// Element to scroll into view. Must be a known element with a recorded position.
    public let elementTarget: ElementTarget?
    public init(elementTarget: ElementTarget? = nil) {
        self.elementTarget = elementTarget
    }
}

extension ScrollToVisibleTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToVisible", [
            elementTarget?.description,
        ].compactMap { $0 })
    }
}

/// Target for iterative element search.
/// Pages through scroll content looking for an element that may not be in the registry.
public struct ElementSearchTarget: Sendable {
    /// Element to search for while scrolling.
    public let elementTarget: ElementTarget?
    /// Starting scroll direction (default: .down)
    public let direction: ScrollSearchDirection?
    public init(
        elementTarget: ElementTarget? = nil,
        direction: ScrollSearchDirection? = nil
    ) {
        self.elementTarget = elementTarget
        self.direction = direction
    }

    public var resolvedDirection: ScrollSearchDirection { direction ?? .down }
}

extension ElementSearchTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("elementSearch", [
            elementTarget?.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

extension ScrollToVisibleTarget: Codable {
    public init(from decoder: Decoder) throws {
        self.elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
    }
}

extension ElementSearchTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case direction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        self.direction = try container.decodeIfPresent(ScrollSearchDirection.self, forKey: .direction)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(direction, forKey: .direction)
    }
}

/// Edge for scroll-to-edge commands
public enum ScrollEdge: String, Codable, Sendable, CaseIterable {
    case top, bottom, left, right
}

/// Target for scroll-to-edge command
public struct ScrollToEdgeTarget: Sendable {
    /// Explicit scroll container to move.
    public let containerTarget: ScrollContainerTarget?
    /// Compatibility: element whose scrollable container to scroll.
    public let elementTarget: ElementTarget?
    /// Which edge to scroll to
    public let edge: ScrollEdge

    public init(
        elementTarget: ElementTarget? = nil,
        containerTarget: ScrollContainerTarget? = nil,
        edge: ScrollEdge = .top
    ) {
        self.elementTarget = elementTarget
        self.containerTarget = containerTarget
        self.edge = edge
    }

    public var containerSelection: ScrollContainerSelection {
        if let containerTarget {
            return .container(containerTarget)
        }
        if let elementTarget {
            return .element(elementTarget)
        }
        return .visibleContainer
    }
}

extension ScrollToEdgeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToEdge", [
            containerTarget?.description,
            elementTarget?.description,
            ScoreDescription.valueField("edge", edge),
        ].compactMap { $0 })
    }
}

extension ScrollToEdgeTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case edge
        case container
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.containerTarget = try container.decodeIfPresent(ScrollContainerTarget.self, forKey: .container)
        self.elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        self.edge = try container.decodeIfPresent(ScrollEdge.self, forKey: .edge) ?? .top
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(containerTarget, forKey: .container)
        try container.encode(edge, forKey: .edge)
    }
}
