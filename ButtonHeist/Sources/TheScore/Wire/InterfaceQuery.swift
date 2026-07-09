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
        precondition(
            subtree == nil || !matcher.hasPredicates,
            "interface query accepts subtree or matcher, not both"
        )
        self.subtree = subtree
        self.matcher = matcher
        self.maxScrollsPerContainer = Self.checkedDiscoveryLimit(
            maxScrollsPerContainer,
            field: InterfaceQueryCodingKeys.maxScrollsPerContainer.stringValue
        )
        self.maxScrollsPerDiscovery = Self.checkedDiscoveryLimit(
            maxScrollsPerDiscovery,
            field: InterfaceQueryCodingKeys.maxScrollsPerDiscovery.stringValue
        )
    }
}

extension InterfaceQuery: Codable {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: InterfaceQueryCodingKeys.self, typeName: "interface query")
        let container = try decoder.container(keyedBy: InterfaceQueryCodingKeys.self)
        let subtree = try container.decodeIfPresent(SubtreeSelector.self, forKey: .subtree)
        let matcher = try container.decodeIfPresent(ElementPredicate.self, forKey: .matcher) ?? ElementPredicate()
        if subtree != nil, matcher.hasPredicates {
            throw DecodingError.dataCorruptedError(
                forKey: .matcher,
                in: container,
                debugDescription: "interface query accepts subtree or matcher, not both"
            )
        }
        self.subtree = subtree
        self.matcher = matcher
        self.maxScrollsPerContainer = try Self.decodeDiscoveryLimit(
            from: container,
            forKey: .maxScrollsPerContainer
        )
        self.maxScrollsPerDiscovery = try Self.decodeDiscoveryLimit(
            from: container,
            forKey: .maxScrollsPerDiscovery
        )
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

private extension InterfaceQuery {
    static let discoveryLimitRange = 1...2_000

    static func checkedDiscoveryLimit(_ value: Int?, field: String) -> Int? {
        guard let value else { return nil }
        precondition(
            discoveryLimitRange.contains(value),
            "\(field) must be between \(discoveryLimitRange.lowerBound) and \(discoveryLimitRange.upperBound)"
        )
        return value
    }

    static func decodeDiscoveryLimit(
        from container: KeyedDecodingContainer<InterfaceQueryCodingKeys>,
        forKey key: InterfaceQueryCodingKeys
    ) throws -> Int? {
        guard let value = try container.decodeIfPresent(Int.self, forKey: key) else { return nil }
        guard discoveryLimitRange.contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(key.stringValue) must be between "
                    + "\(discoveryLimitRange.lowerBound) and \(discoveryLimitRange.upperBound)"
            )
        }
        return value
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
