import ThePlans
import Foundation

private enum InterfaceQueryCodingKeys: String, CodingKey, CaseIterable {
    case subtree
    case maxScrollsPerContainer
    case maxScrollsPerDiscovery
}

public struct InterfaceQuery: Sendable, Equatable {
    public let subtree: AccessibilityTarget?
    public let maxScrollsPerContainer: Int?
    public let maxScrollsPerDiscovery: Int?

    public init(
        subtree: AccessibilityTarget? = nil,
        maxScrollsPerContainer: Int? = nil,
        maxScrollsPerDiscovery: Int? = nil
    ) {
        self.subtree = subtree
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
        self.subtree = try container.decodeIfPresent(AccessibilityTarget.self, forKey: .subtree)
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
            maxScrollsPerContainer.map { "maxScrollsPerContainer=\($0)" },
            maxScrollsPerDiscovery.map { "maxScrollsPerDiscovery=\($0)" },
        ].compactMap { $0 })
    }
}
