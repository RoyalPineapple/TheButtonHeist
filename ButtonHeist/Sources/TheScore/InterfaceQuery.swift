import ThePlans
import Foundation

private enum InterfaceQueryCodingKeys: String, CodingKey, CaseIterable {
    case subtree
    case matcher
}

public struct InterfaceQuery: Sendable, Equatable {
    public let subtree: SubtreeSelector?
    public let matcher: ElementPredicate

    public init(
        subtree: SubtreeSelector? = nil,
        matcher: ElementPredicate = ElementPredicate()
    ) {
        self.subtree = subtree
        self.matcher = matcher
    }
}

extension InterfaceQuery: Codable {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: InterfaceQueryCodingKeys.self, typeName: "interface query")
        let container = try decoder.container(keyedBy: InterfaceQueryCodingKeys.self)
        self.subtree = try container.decodeIfPresent(SubtreeSelector.self, forKey: .subtree)
        self.matcher = try container.decodeIfPresent(ElementPredicate.self, forKey: .matcher) ?? ElementPredicate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: InterfaceQueryCodingKeys.self)
        try container.encodeIfPresent(subtree, forKey: .subtree)
        if matcher.hasPredicates {
            try container.encode(matcher, forKey: .matcher)
        }
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
