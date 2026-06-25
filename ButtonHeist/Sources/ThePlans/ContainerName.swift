import Foundation

/// Button Heist's generated name for a container in the current interface capture.
public struct ContainerName: RawRepresentable, Hashable, Sendable, Equatable, CustomStringConvertible,
    ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    /// Parse a public/wire container name, normalizing surrounding whitespace and rejecting blanks.
    public init?(parsing value: String) {
        let rawValue = Self.normalizedRawValue(value)
        guard !rawValue.isEmpty else { return nil }
        self.init(rawValue: rawValue)
    }

    public var description: String {
        rawValue
    }

    public var isEmpty: Bool {
        rawValue.isEmpty
    }

    private static func normalizedRawValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ContainerName: Comparable {
    public static func < (lhs: ContainerName, rhs: ContainerName) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension ContainerName: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let containerName = ContainerName(parsing: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "container name must be non-empty"
            )
        }
        self = containerName
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
