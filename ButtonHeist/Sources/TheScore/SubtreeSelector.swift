import Foundation

// MARK: - Subtree Selection

/// Selector for projecting an `Interface` to one matched node.
///
/// `.element` searches leaf `HeistElement` nodes by current-capture handle or
/// `ElementMatcher`. `.container` searches parser container nodes with
/// `ContainerMatcher`. `ordinal` is applied only after semantic narrowing.
public enum SubtreeSelector: Codable, Sendable, Equatable {
    case element(ElementTarget)
    case container(ContainerMatcher, ordinal: Int? = nil)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case container
        case ordinal
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "subtree selector")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasElement = container.contains(.element)
        let hasContainer = container.contains(.container)
        guard hasElement != hasContainer else {
            throw DecodingError.dataCorruptedError(
                forKey: .element,
                in: container,
                debugDescription: "SubtreeSelector requires exactly one of element or container"
            )
        }
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if let ordinal, ordinal < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: "ordinal must be non-negative, got \(ordinal)"
            )
        }
        if hasElement {
            self = .element(try ElementTarget.decodeSubtreeElement(
                from: container.superDecoder(forKey: .element),
                ordinal: ordinal
            ))
        } else {
            self = .container(try container.decode(ContainerMatcher.self, forKey: .container), ordinal: ordinal)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let target):
            var element = container.nestedContainer(keyedBy: ElementTarget.CodingKeys.self, forKey: .element)
            switch target {
            case .heistId(let heistId):
                try element.encode(heistId, forKey: .heistId)
            case .matcher(let matcher, let ordinal):
                try element.encodeIfPresent(matcher.label, forKey: .label)
                try element.encodeIfPresent(matcher.identifier, forKey: .identifier)
                try element.encodeIfPresent(matcher.value, forKey: .value)
                try element.encodeIfPresent(matcher.traits, forKey: .traits)
                try element.encodeIfPresent(matcher.excludeTraits, forKey: .excludeTraits)
                try container.encodeIfPresent(ordinal, forKey: .ordinal)
            }
        case .container(let matcher, let ordinal):
            try container.encode(matcher, forKey: .container)
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        }
    }

    public var ordinal: Int? {
        switch self {
        case .element(.matcher(_, let ordinal)), .container(_, let ordinal):
            return ordinal
        case .element(.heistId):
            return nil
        }
    }

    public var hasPredicates: Bool {
        switch self {
        case .element(.heistId(let heistId)):
            return !heistId.isEmpty
        case .element(.matcher(let matcher, _)):
            return matcher.hasPredicates
        case .container(let matcher, _):
            return matcher.hasPredicates
        }
    }
}

extension SubtreeSelector: CustomStringConvertible {
    public var description: String {
        switch self {
        case .element(let target):
            return ScoreDescription.call("subtree.element", [
                target.description,
            ].compactMap { $0 })
        case .container(let matcher, let ordinal):
            return ScoreDescription.call("subtree.container", [
                matcher.description,
                ScoreDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        }
    }
}
