import Foundation

/// Shared mechanics for open string values whose identity is their exact, nonblank spelling.
public protocol NonBlankStringValue: Codable, Sendable, Hashable, Equatable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    init(validating value: String) throws
}

public extension NonBlankStringValue {
    init(stringLiteral value: String) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }

    init(from decoder: Decoder) throws {
        self = try decodeSingleValue(from: decoder, admitting: Self.init(validating:))
    }

    func encode(to encoder: Encoder) throws {
        try encodeSingleValue(description, to: encoder)
    }
}

private struct BlankStringValueError: Error, CustomStringConvertible {
    let kind: String

    var description: String { "\(kind) must not be blank" }
}

package func validateNonBlank(_ value: String, kind: String = "value") throws -> String {
    guard value.contains(where: { !$0.isWhitespace }) else {
        throw BlankStringValueError(kind: kind)
    }
    return value
}

package struct BoundedSeconds: Sendable, Equatable {
    package let value: Double

    package init(value: Double, maximum: Double) throws(BoundedSecondsError) {
        guard value.isFinite,
              value > 0,
              value <= maximum else {
            throw BoundedSecondsError(
                observed: value,
                expected: "finite number greater than 0 and no more than \(ScoreDescription.decimal(maximum))"
            )
        }
        self.value = value
    }
}

package struct BoundedSecondsError: Error, Sendable, Equatable {
    package let observed: Double
    package let expected: String
}

package func requireNonEmpty<Failure: Error>(
    _ value: String,
    or failure: @autoclosure () -> Failure
) throws -> String {
    guard !value.isEmpty else { throw failure() }
    return value
}

package func decodeSingleValue<Payload: Decodable, Value>(
    from decoder: Decoder,
    admitting: (Payload) throws -> Value
) throws -> Value {
    let container = try decoder.singleValueContainer()
    do {
        return try admitting(container.decode(Payload.self))
    } catch {
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: String(describing: error)
        )
    }
}

package func encodeSingleValue<Payload: Encodable>(_ value: Payload, to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
}

public struct TextInputText: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public enum Mode: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
        case append
        case replace
    }

    public let mode: Mode
    private let text: String

    public init(validating text: String) throws(TextInputTextError) {
        try self.init(validating: text, mode: .append)
    }

    public init(validating text: String, mode: Mode) throws(TextInputTextError) {
        guard mode == .replace || !text.isEmpty else {
            throw TextInputTextError.emptyAppend
        }
        self.init(mode: mode, text: text)
    }

    public static func replacing(_ text: String) -> Self {
        Self(mode: .replace, text: text)
    }

    package var rawText: String { text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "type text value")
        let text = try container.decode(String.self, forKey: .text)
        let mode = try container.decode(Mode.self, forKey: .mode)
        do {
            self = try Self(validating: text, mode: mode)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(mode, forKey: .mode)
    }

    public var description: String { text }

    private init(mode: Mode, text: String) {
        self.mode = mode
        self.text = text
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text, mode
    }
}

extension TextInputText: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload {
            try Self(validating: value)
        }
    }
}

public enum TextInputTextError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyAppend

    public var description: String {
        "text to append must be non-empty"
    }
}

public struct PasteboardText: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    private let text: String

    public init(validating text: String) throws {
        self.text = try requireNonEmpty(text, or: PasteboardTextError.empty)
    }

    package var rawText: String { text }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValue(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValue(text, to: encoder)
    }

    public var description: String { text }
}

extension PasteboardText: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload {
            try Self(validating: value)
        }
    }
}

public enum PasteboardTextError: Error, Sendable, Equatable, CustomStringConvertible {
    case empty

    public var description: String {
        "pasteboard text must be non-empty"
    }
}

public struct CustomActionName: NonBlankStringValue {
    private let value: String

    public init(validating value: String) throws {
        self.value = try validateNonBlank(value, kind: "custom action name")
    }

    package var rawValue: String { value }

    public var description: String { value }
}

public struct RotorName: NonBlankStringValue {
    private let value: String

    public init(validating value: String) throws {
        self.value = try validateNonBlank(value, kind: "rotor name")
    }

    package var rawValue: String { value }

    public var description: String { value }
}

public struct HeistWarningMessage: NonBlankStringValue {
    private let value: String

    public init(validating value: String) throws {
        self.value = try validateNonBlank(value, kind: "heist warning message")
    }

    package var rawValue: String { value }

    public var description: String { value }
}

public struct HeistFailureMessage: NonBlankStringValue {
    private let value: String

    public init(validating value: String) throws {
        self.value = try validateNonBlank(value, kind: "heist failure message")
    }

    package var rawValue: String { value }

    public var description: String { value }
}

package func requireValidLiteralPayload<Value>(_ construct: () throws -> Value) -> Value {
    do {
        return try construct()
    } catch {
        preconditionFailure(String(describing: error))
    }
}
