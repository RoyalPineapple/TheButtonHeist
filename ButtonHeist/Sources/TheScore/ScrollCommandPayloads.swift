import Foundation

/// Direction for scroll actions
public enum ScrollDirection: String, Codable, Sendable, CaseIterable, Equatable {
    case up, down, left, right
}

public enum ScrollContainerSelection: Sendable, Equatable, CustomStringConvertible {
    case visibleContainer
    case element(ElementTarget)

    public var description: String {
        switch self {
        case .visibleContainer:
            return "visibleContainer"
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

    private var elementTarget: ElementTarget? {
        guard case .element(let target) = selection else { return nil }
        return target
    }
}

extension ScrollTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scroll", [
            elementTarget?.description,
            ScoreDescription.valueField("direction", direction),
        ].compactMap { $0 })
    }
}

extension ScrollTarget: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case direction
        case container
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownScrollPayloadKeys(
            from: decoder,
            commandFields: [CodingKeys.direction.stringValue],
            allowsContainerKey: true,
            typeName: "scroll target"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasContainerTarget = container.contains(.container)
        let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        if hasContainerTarget {
            throw DecodingError.dataCorruptedError(
                forKey: .container,
                in: container,
                debugDescription: "ScrollTarget does not accept public container handles; target an element inside the intended scroll region"
            )
        }
        switch elementTarget {
        case .some(let elementTarget):
            self.selection = .element(elementTarget)
        case nil:
            self.selection = .visibleContainer
        }
        self.direction = try container.decode(ScrollDirection.self, forKey: .direction)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
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
}

extension ScrollToEdgeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("scrollToEdge", [
            elementTarget?.description,
            ScoreDescription.valueField("edge", edge),
        ].compactMap { $0 })
    }
}

extension ScrollToEdgeTarget: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case edge
        case container
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownScrollPayloadKeys(
            from: decoder,
            commandFields: [CodingKeys.edge.stringValue],
            allowsContainerKey: true,
            typeName: "scroll_to_edge target"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasContainerTarget = container.contains(.container)
        let elementTarget = try ElementTarget.decodeInlineIfPresent(from: decoder)
        if hasContainerTarget {
            throw DecodingError.dataCorruptedError(
                forKey: .container,
                in: container,
                debugDescription: "ScrollToEdgeTarget does not accept public container handles; target an element inside the intended scroll region"
            )
        }
        switch elementTarget {
        case .some(let elementTarget):
            self.selection = .element(elementTarget)
        case nil:
            self.selection = .visibleContainer
        }
        self.edge = try container.decode(ScrollEdge.self, forKey: .edge)
    }

    public func encode(to encoder: Encoder) throws {
        if let elementTarget { try elementTarget.encode(to: encoder) }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edge, forKey: .edge)
    }
}

private func rejectUnknownScrollPayloadKeys(
    from decoder: Decoder,
    commandFields: [String] = [],
    allowsContainerKey: Bool = false,
    typeName: String
) throws {
    let containerKeys = allowsContainerKey ? ["container"] : []
    let allowed = Set(ElementTarget.inlineFieldNames + commandFields + containerKeys)
    try decoder.rejectUnknownKeys(allowed: allowed, typeName: typeName)
}
