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

/// Target for waitForIdle command
public struct WaitForIdleTarget: Codable, Sendable {
    /// Maximum time to wait in seconds (default 5.0)
    public let timeout: Double?

    public init(timeout: Double? = nil) {
        self.timeout = timeout
    }
}

extension WaitForIdleTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitForIdle", [
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// Target for wait_for_change command — wait for the UI to change in a way
/// that matches an expectation. With no expectation, returns on any tree change.
public struct WaitForChangeTarget: Codable, Sendable {
    /// The change to wait for. When nil, any tree change satisfies the wait.
    public let expect: ActionExpectation?
    /// Maximum time to wait in seconds (default: 30, max: 30)
    public let timeout: Double?

    public init(expect: ActionExpectation? = nil, timeout: Double? = nil) {
        self.expect = expect
        self.timeout = timeout
    }

    public var resolvedTimeout: Double { min(timeout ?? 30, 30) }
}

extension WaitForChangeTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitForChange", [
            expect?.description,
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// Target for wait_for command — wait for an element to appear or disappear.
/// Uses ElementTarget so both heistId and matcher predicates work.
public struct WaitForTarget: Sendable {
    /// Element to wait for — by heistId or matcher predicate.
    public let elementTarget: ElementTarget
    /// When true, wait for the element to NOT exist
    public let absent: Bool?
    /// Maximum time to wait in seconds (default: 10, max: 30)
    public let timeout: Double?

    public init(elementTarget: ElementTarget, absent: Bool? = nil, timeout: Double? = nil) {
        self.elementTarget = elementTarget
        self.absent = absent
        self.timeout = timeout
    }

    public var resolvedAbsent: Bool { absent ?? false }
    public var resolvedTimeout: Double { min(timeout ?? 10, 30) }
}

extension WaitForTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitFor", [
            elementTarget.description,
            ScoreDescription.valueField("absent", absent),
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

extension WaitForTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case absent, timeout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // WaitForTarget requires an inline ElementTarget — defer to ElementTarget's
        // own validation (it throws when no matcher/heistId keys are present).
        self.elementTarget = try ElementTarget(from: decoder)
        self.absent = try container.decodeIfPresent(Bool.self, forKey: .absent)
        self.timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try elementTarget.encode(to: encoder)
        try container.encodeIfPresent(absent, forKey: .absent)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }
}
