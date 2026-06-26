import Foundation

public struct SettledObservationSequence:
    RawRepresentable,
    Codable,
    Sendable,
    Hashable,
    Comparable,
    ExpressibleByIntegerLiteral,
    CustomStringConvertible {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: UInt64) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UInt64.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue.description
    }

    public static func < (lhs: SettledObservationSequence, rhs: SettledObservationSequence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func + (lhs: SettledObservationSequence, rhs: UInt64) -> SettledObservationSequence {
        SettledObservationSequence(lhs.rawValue + rhs)
    }

    public static func - (lhs: SettledObservationSequence, rhs: UInt64) -> SettledObservationSequence {
        SettledObservationSequence(lhs.rawValue - rhs)
    }

    public static func += (lhs: inout SettledObservationSequence, rhs: UInt64) {
        lhs = lhs + rhs
    }
}
