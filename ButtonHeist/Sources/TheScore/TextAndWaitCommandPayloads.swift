import Foundation

/// Target for typing non-empty text character-by-character via keyboard key taps.
public struct TypeTextTarget: Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case text
        case elementTarget
    }

    /// Text to type (each character is tapped individually).
    public let text: String
    /// Optional element to tap first to bring up keyboard (text field).
    /// Also used to read back the current value after typing.
    public let elementTarget: ElementTarget?

    public init(text: String, elementTarget: ElementTarget? = nil) {
        self.text = text
        self.elementTarget = elementTarget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        guard !text.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.text],
                debugDescription: "text must be non-empty"
            ))
        }
        elementTarget = try container.decodeIfPresent(ElementTarget.self, forKey: .elementTarget)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(elementTarget, forKey: .elementTarget)
    }
}

extension TypeTextTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("typeText", [
            ScoreDescription.stringField("text", text),
            elementTarget?.description,
        ].compactMap { $0 })
    }
}

/// Standard edit actions that can be dispatched via the responder chain.
public enum EditAction: String, Codable, Sendable, CaseIterable {
    case copy, paste, cut, select, selectAll, delete
}

/// Target for writing text to the general pasteboard.
public struct SetPasteboardTarget: Codable, Sendable {
    /// Text to write to the pasteboard
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

extension SetPasteboardTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("pasteboard", [
            ScoreDescription.stringField("text", text),
        ].compactMap { $0 })
    }
}

/// Target for edit actions dispatched via the responder chain
public struct EditActionTarget: Codable, Sendable {
    /// The edit action to perform
    public let action: EditAction

    public init(action: EditAction) {
        self.action = action
    }
}

extension EditActionTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("editAction", [
            ScoreDescription.valueField("action", action),
        ].compactMap { $0 })
    }
}

/// Target for the `wait` command — wait until an accessibility predicate is
/// satisfied. `present`/`absent` poll the current interface; `changed` rides
/// through intermediate states until the change predicate is met.
public struct WaitTarget: Codable, Sendable, Equatable {
    /// The predicate to wait on.
    public let predicate: AccessibilityPredicate
    /// Maximum time to wait in seconds (default: 10, max: 30)
    public let timeout: Double?

    public init(predicate: AccessibilityPredicate, timeout: Double? = nil) {
        self.predicate = predicate
        self.timeout = timeout
    }

    public var resolvedTimeout: Double { min(timeout ?? 10, 30) }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "wait target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        self.timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }
}

extension WaitTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("wait", [
            predicate.description,
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}
