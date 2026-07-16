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

private func requireNonEmpty<Failure: Error>(
    _ value: String,
    or failure: @autoclosure () -> Failure
) throws -> String {
    guard !value.isEmpty else { throw failure() }
    return value
}

private func requireNonBlank<Failure: Error>(
    _ value: String,
    or failure: @autoclosure () -> Failure
) throws -> String {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw failure()
    }
    return value
}

private func decodeSingleValueString<Value>(
    from decoder: Decoder,
    admitting: (String) throws -> Value
) throws -> Value {
    let container = try decoder.singleValueContainer()
    do {
        return try admitting(container.decode(String.self))
    } catch {
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: String(describing: error)
        )
    }
}

private func encodeSingleValueString(_ value: String, to encoder: Encoder) throws {
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
        self = try decodeSingleValueString(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValueString(text, to: encoder)
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

public struct CustomActionName: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    private let value: String

    public init(validating value: String) throws {
        self.value = try requireNonBlank(value, or: CustomActionNameError.blank)
    }

    package var rawValue: String { value }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValueString(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValueString(value, to: encoder)
    }

    public var description: String { value }
}

extension CustomActionName: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public enum CustomActionNameError: Error, Sendable, Equatable, CustomStringConvertible {
    case blank

    public var description: String { "custom action name must not be blank" }
}

public struct RotorName: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    private let value: String

    public init(validating value: String) throws {
        self.value = try requireNonBlank(value, or: RotorNameError.blank)
    }

    package var rawValue: String { value }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValueString(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValueString(value, to: encoder)
    }

    public var description: String { value }
}

extension RotorName: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public enum RotorNameError: Error, Sendable, Equatable, CustomStringConvertible {
    case blank

    public var description: String { "rotor name must not be blank" }
}

public struct HeistWarningMessage: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    private let value: String

    public init(validating value: String) throws {
        self.value = try requireNonBlank(value, or: HeistWarningMessageError.blank)
    }

    package var rawValue: String { value }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValueString(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValueString(value, to: encoder)
    }

    public var description: String { value }
}

extension HeistWarningMessage: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public enum HeistWarningMessageError: Error, Sendable, Equatable, CustomStringConvertible {
    case blank

    public var description: String { "heist warning message must not be blank" }
}

public struct HeistFailureMessage: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    private let value: String

    public init(validating value: String) throws {
        self.value = try requireNonBlank(value, or: HeistFailureMessageError.blank)
    }

    package var rawValue: String { value }

    public init(from decoder: Decoder) throws {
        self = try decodeSingleValueString(from: decoder, admitting: Self.init(validating:))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeSingleValueString(value, to: encoder)
    }

    public var description: String { value }
}

extension HeistFailureMessage: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = requireValidLiteralPayload { try Self(validating: value) }
    }
}

public enum HeistFailureMessageError: Error, Sendable, Equatable, CustomStringConvertible {
    case blank

    public var description: String { "heist failure message must not be blank" }
}

func requireValidLiteralPayload<Value>(_ construct: () throws -> Value) -> Value {
    do {
        return try construct()
    } catch {
        preconditionFailure(String(describing: error))
    }
}
