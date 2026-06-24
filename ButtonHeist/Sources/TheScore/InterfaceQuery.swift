import ThePlans
import Foundation

private enum InterfaceQueryCodingKeys: String, CodingKey, CaseIterable {
    case subtree
    case matcher
    case maxScrollsPerContainer
    case maxScrollsPerDiscovery
}

public struct InterfaceQuery: Sendable, Equatable {
    public let subtree: SubtreeSelector?
    public let matcher: ElementPredicate
    public let maxScrollsPerContainer: Int?
    public let maxScrollsPerDiscovery: Int?

    public init(
        subtree: SubtreeSelector? = nil,
        matcher: ElementPredicate = ElementPredicate(),
        maxScrollsPerContainer: Int? = nil,
        maxScrollsPerDiscovery: Int? = nil
    ) {
        self.subtree = subtree
        self.matcher = matcher
        self.maxScrollsPerContainer = maxScrollsPerContainer
        self.maxScrollsPerDiscovery = maxScrollsPerDiscovery
    }
}

extension InterfaceQuery: Codable {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: InterfaceQueryCodingKeys.self, typeName: "interface query")
        let container = try decoder.container(keyedBy: InterfaceQueryCodingKeys.self)
        self.subtree = try container.decodeIfPresent(SubtreeSelector.self, forKey: .subtree)
        self.matcher = try container.decodeIfPresent(ElementPredicate.self, forKey: .matcher) ?? ElementPredicate()
        self.maxScrollsPerContainer = try container.decodeIfPresent(Int.self, forKey: .maxScrollsPerContainer)
        self.maxScrollsPerDiscovery = try container.decodeIfPresent(Int.self, forKey: .maxScrollsPerDiscovery)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: InterfaceQueryCodingKeys.self)
        try container.encodeIfPresent(subtree, forKey: .subtree)
        if matcher.hasPredicates {
            try container.encode(matcher, forKey: .matcher)
        }
        try container.encodeIfPresent(maxScrollsPerContainer, forKey: .maxScrollsPerContainer)
        try container.encodeIfPresent(maxScrollsPerDiscovery, forKey: .maxScrollsPerDiscovery)
    }

}

extension InterfaceQuery: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("interfaceQuery", [
            subtree?.description,
            matcher.hasPredicates ? matcher.description : nil,
            maxScrollsPerContainer.map { "maxScrollsPerContainer=\($0)" },
            maxScrollsPerDiscovery.map { "maxScrollsPerDiscovery=\($0)" },
        ].compactMap { $0 })
    }
}
