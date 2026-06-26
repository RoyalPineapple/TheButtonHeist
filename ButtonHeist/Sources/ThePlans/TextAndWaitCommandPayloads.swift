import Foundation

/// Target for typing non-empty text character-by-character via keyboard key taps.
public struct TypeTextTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
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

    public init(validatingText text: String, elementTarget: ElementTarget? = nil) throws {
        try Self.validate(text)
        self.init(text: text, elementTarget: elementTarget)
    }

    public static func validate(_ text: String) throws {
        guard !text.isEmpty else {
            throw TypeTextTargetError.emptyText
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "type text target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        do {
            try Self.validate(text)
        } catch {
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

public enum TypeTextTargetError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyText

    public var description: String {
        switch self {
        case .emptyText:
            return "text must be non-empty"
        }
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
public enum EditAction: String, Codable, Sendable, CaseIterable, Equatable {
    case copy, paste, cut, select, selectAll, delete
}

/// Target for writing text to the general pasteboard.
public struct SetPasteboardTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
    }

    /// Text to write to the pasteboard
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public init(validatingText text: String) throws {
        try Self.validate(text)
        self.init(text: text)
    }

    public static func validate(_ text: String) throws {
        guard !text.isEmpty else {
            throw SetPasteboardTargetError.emptyText
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "pasteboard target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        do {
            try Self.validate(text)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.text],
                debugDescription: "pasteboard text must be non-empty"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
    }
}

public enum SetPasteboardTargetError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyText

    public var description: String {
        switch self {
        case .emptyText:
            return "pasteboard text must be non-empty"
        }
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
public struct EditActionTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case action
    }

    /// The edit action to perform
    public let action: EditAction

    public init(action: EditAction) {
        self.action = action
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "edit action target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(EditAction.self, forKey: .action)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
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
/// satisfied. State predicates poll the current interface; change predicates
/// ride through intermediate settled states until the requested change is met.
public struct WaitTarget: Codable, Sendable, Equatable {
    /// The predicate to wait on.
    public let predicate: AccessibilityPredicate
    /// Maximum time to wait in seconds (default: 30, max: 30).
    public let timeout: Double?

    public init(predicate: AccessibilityPredicate, timeout: Double? = nil) {
        self.predicate = predicate
        self.timeout = timeout
    }

    public var resolvedTimeout: Double { min(timeout ?? defaultWaitTimeout, defaultWaitTimeout) }

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
