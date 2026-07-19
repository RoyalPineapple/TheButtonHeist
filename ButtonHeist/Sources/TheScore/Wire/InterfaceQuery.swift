import ThePlans
import Foundation

private enum InterfaceQueryCodingKeys: String, CodingKey, CaseIterable {
    case subtree
    case maxScrollsPerContainer
    case maxScrollsPerDiscovery
}

public struct InterfaceDiscoveryLimit: Codable, Sendable, Equatable, CustomStringConvertible {
    public static let allowedRange = 1...2_000

    public let value: Int

    public init(validating value: Int) throws {
        guard Self.allowedRange.contains(value) else {
            throw InvalidInterfaceDiscoveryLimitError()
        }
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValue(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValue(value, to: encoder)
    }

    public var description: String { value.description }
}

private struct InvalidInterfaceDiscoveryLimitError: Error, CustomStringConvertible {
    var description: String {
        "interface discovery limit must be between "
            + "\(InterfaceDiscoveryLimit.allowedRange.lowerBound) and "
            + "\(InterfaceDiscoveryLimit.allowedRange.upperBound)"
    }
}

extension InterfaceDiscoveryLimit: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public struct InterfaceQuery: Sendable, Equatable {
    public let subtree: AccessibilityTarget?
    public let maxScrollsPerContainer: InterfaceDiscoveryLimit?
    public let maxScrollsPerDiscovery: InterfaceDiscoveryLimit?

    public init(
        subtree: AccessibilityTarget? = nil,
        maxScrollsPerContainer: InterfaceDiscoveryLimit? = nil,
        maxScrollsPerDiscovery: InterfaceDiscoveryLimit? = nil
    ) {
        self.subtree = subtree
        self.maxScrollsPerContainer = maxScrollsPerContainer
        self.maxScrollsPerDiscovery = maxScrollsPerDiscovery
    }
}

extension InterfaceQuery: Codable {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: InterfaceQueryCodingKeys.self, typeName: "interface query")
        let container = try decoder.container(keyedBy: InterfaceQueryCodingKeys.self)
        self.subtree = try container.decodeIfPresent(AccessibilityTarget.self, forKey: .subtree)
        self.maxScrollsPerContainer = try container.decodeIfPresent(
            InterfaceDiscoveryLimit.self,
            forKey: .maxScrollsPerContainer
        )
        self.maxScrollsPerDiscovery = try container.decodeIfPresent(
            InterfaceDiscoveryLimit.self,
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

extension InterfaceQuery: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("interfaceQuery", [
            subtree?.description,
            maxScrollsPerContainer.map { "maxScrollsPerContainer=\($0)" },
            maxScrollsPerDiscovery.map { "maxScrollsPerDiscovery=\($0)" },
        ].compactMap { $0 })
    }
}
