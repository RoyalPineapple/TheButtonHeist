import Foundation

private enum InterfaceQueryCodingKeys: String, CodingKey, CaseIterable {
    case subtree
    case matcher
}

private struct InterfaceQueryUnknownKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

public struct InterfaceQuery: Sendable, Equatable {
    public let subtree: SubtreeSelector?
    public let matcher: ElementMatcher

    public init(
        subtree: SubtreeSelector? = nil,
        matcher: ElementMatcher = ElementMatcher()
    ) {
        self.subtree = subtree
        self.matcher = matcher
    }
}

extension InterfaceQuery: Codable {
    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(decoder)
        let container = try decoder.container(keyedBy: InterfaceQueryCodingKeys.self)
        self.subtree = try container.decodeIfPresent(SubtreeSelector.self, forKey: .subtree)
        self.matcher = try container.decodeIfPresent(ElementMatcher.self, forKey: .matcher) ?? ElementMatcher()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: InterfaceQueryCodingKeys.self)
        try container.encodeIfPresent(subtree, forKey: .subtree)
        if matcher.hasPredicates {
            try container.encode(matcher, forKey: .matcher)
        }
    }

    private static func rejectUnknownKeys(_ decoder: Decoder) throws {
        let knownKeys = Set(InterfaceQueryCodingKeys.allCases.map(\.stringValue))
        let dynamicContainer = try decoder.container(keyedBy: InterfaceQueryUnknownKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [unknownKey],
            debugDescription: "Unknown interface query field \"\(unknownKey.stringValue)\""
        ))
    }
}

extension InterfaceQuery: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("interfaceQuery", [
            subtree?.description,
            matcher.hasPredicates ? matcher.description : nil,
        ].compactMap { $0 })
    }
}
