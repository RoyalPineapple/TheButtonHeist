import Foundation

/// Direction for scroll actions
public enum ScrollDirection: String, Codable, Sendable, CaseIterable, Equatable {
    case up, down, left, right
}

/// Target for container-moving scroll commands.
public struct ScrollContainerTarget: Codable, Sendable, Equatable {
    /// Stable container id returned by get_interface.
    public let stableId: HeistContainer?

    public init(stableId: HeistContainer? = nil) {
        self.stableId = stableId
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case stableId
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "ScrollContainerTarget")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(stableId: try container.decodeIfPresent(HeistContainer.self, forKey: .stableId))
    }
}

extension ScrollContainerTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("container", [
            ScoreDescription.stringField("stableId", stableId),
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

    public init(
        containerTarget: ScrollContainerTarget,
        direction: ScrollDirection = .down
    ) {
        self.init(selection: .container(containerTarget), direction: direction)
    }

    private var containerTarget: ScrollContainerTarget? {
        guard case .container(let target) = selection else { return nil }
        return target
    }

    private var elementTarget: ElementTarget? {
        guard case .element(let target) = selection else { return nil }
        return target
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
        let containerTarget = try container.decodeIfPresent(ScrollContainerTarget.self, forKey: .container)
        let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        switch (containerTarget, elementTarget) {
        case (.some, .some):
            throw DecodingError.dataCorruptedError(
                forKey: .container,
                in: container,
                debugDescription: "ScrollTarget requires at most one of container or element target"
            )
        case (.some(let containerTarget), nil):
            self.selection = .container(containerTarget)
        case (nil, .some(let elementTarget)):
            self.selection = .element(elementTarget)
        case (nil, nil):
            self.selection = .visibleContainer
        }
        self.direction = try container.decode(ScrollDirection.self, forKey: .direction)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(containerTarget, forKey: .container)
        try container.encode(direction, forKey: .direction)
    }
}

/// Target for one-shot scroll-to-visible.
/// The element must be known (in the registry with a content-space position).
/// Jumps directly to the element's position — no iterative search.
public struct ScrollToVisibleTarget: Sendable, Equatable {
    /// Element to scroll into view. Must be a known element with a recorded position.
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

/// Target for iterative element search.
/// Pages through scroll content looking for an element that may not be in the registry.
public struct ElementSearchTarget: Sendable, Equatable {
    /// Element to search for while scrolling.
    public let elementTarget: ElementTarget
    /// Starting scroll direction.
    public let direction: ScrollDirection
    public init(
        elementTarget: ElementTarget,
        direction: ScrollDirection = .down
    ) {
        self.elementTarget = elementTarget
        self.direction = direction
    }
}

extension ElementSearchTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("elementSearch", [
            elementTarget.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

extension ScrollToVisibleTarget: Codable {
    public init(from decoder: Decoder) throws {
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

extension ElementSearchTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case direction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "ElementSearchTarget requires an element target"
                )
            )
        }
        self.elementTarget = elementTarget
        self.direction = try container.decode(ScrollDirection.self, forKey: .direction)
    }

    public func encode(to encoder: Encoder) throws {
        try elementTarget.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(direction, forKey: .direction)
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

    public init(
        containerTarget: ScrollContainerTarget,
        edge: ScrollEdge = .top
    ) {
        self.init(selection: .container(containerTarget), edge: edge)
    }

    private var containerTarget: ScrollContainerTarget? {
        guard case .container(let target) = selection else { return nil }
        return target
    }

    private var elementTarget: ElementTarget? {
        guard case .element(let target) = selection else { return nil }
        return target
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
        let containerTarget = try container.decodeIfPresent(ScrollContainerTarget.self, forKey: .container)
        let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        switch (containerTarget, elementTarget) {
        case (.some, .some):
            throw DecodingError.dataCorruptedError(
                forKey: .container,
                in: container,
                debugDescription: "ScrollToEdgeTarget requires at most one of container or element target"
            )
        case (.some(let containerTarget), nil):
            self.selection = .container(containerTarget)
        case (nil, .some(let elementTarget)):
            self.selection = .element(elementTarget)
        case (nil, nil):
            self.selection = .visibleContainer
        }
        self.edge = try container.decode(ScrollEdge.self, forKey: .edge)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(containerTarget, forKey: .container)
        try container.encode(edge, forKey: .edge)
    }
}
