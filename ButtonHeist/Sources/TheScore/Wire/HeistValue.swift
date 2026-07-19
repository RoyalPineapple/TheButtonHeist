import ThePlans
import Foundation

/// A JSON-encodable value type used at command-ingress boundaries.
public enum HeistValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([HeistValue])
    case object([String: HeistValue])

    public init(from decoder: Decoder) throws {
        // Boundary try?: polymorphic decode for `HeistValue`, an any-JSON
        // type that must probe six decoder shapes. Discarded errors are only
        // "wrong type, try the next one"; semantic failure is the explicit
        // `DecodingError.dataCorrupted` below.
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([HeistValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: HeistValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "HeistValue: unsupported JSON type"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let stringValue): try container.encode(stringValue)
        case .int(let intValue): try container.encode(intValue)
        case .double(let doubleValue): try container.encode(doubleValue)
        case .bool(let boolValue): try container.encode(boolValue)
        case .array(let arrayValue): try container.encode(arrayValue)
        case .object(let objectValue): try container.encode(objectValue)
        }
    }
}

extension HeistValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let stringValue):
            return CanonicalValueDescription.quoted(stringValue)
        case .int(let intValue):
            return "\(intValue)"
        case .double(let doubleValue):
            return CanonicalValueDescription.decimal(doubleValue)
        case .bool(let boolValue):
            return "\(boolValue)"
        case .array(let arrayValue):
            return "[\(arrayValue.map(\.description).joined(separator: ", "))]"
        case .object(let objectValue):
            let fields = objectValue
                .sorted { $0.key < $1.key }
                .map { "\(CanonicalValueDescription.quoted($0.key))=\($0.value)" }
            return "{\(fields.joined(separator: ", "))}"
        }
    }
}
