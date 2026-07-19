import Foundation

public enum TextInputSource: Sendable, Equatable {
    case text(TextInputText)
    case reference(HeistReferenceName, mode: TextInputText.Mode)

    public var mode: TextInputText.Mode {
        switch self {
        case .text(let text): text.mode
        case .reference(_, let mode): mode
        }
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> TextInputText {
        switch self {
        case .text(let text):
            return text
        case .reference(let reference, let mode):
            guard let text = environment.strings[reference] else {
                throw HeistExpressionError.unresolvedStringReference(reference.rawValue)
            }
            return try TextInputText(validating: text, mode: mode)
        }
    }
}

/// Target for typing text character-by-character via keyboard key taps.
public struct TypeTextTarget: Codable, Sendable, Equatable {
    /// The typed text source and append/replace semantics.
    public let source: TextInputSource
    /// Optional element to tap first to bring up keyboard (text field).
    /// Also used to read back the current value after typing.
    public let target: AccessibilityTarget?

    public init(text: TextInputText, target: AccessibilityTarget? = nil) {
        source = .text(text)
        self.target = target
    }

    public init(
        reference: HeistReferenceName,
        mode: TextInputText.Mode = .append,
        target: AccessibilityTarget? = nil
    ) {
        source = .reference(reference, mode: mode)
        self.target = target
    }

    package init(source: TextInputSource, target: AccessibilityTarget? = nil) {
        self.source = source
        self.target = target
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "type text target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(TextInputText.Mode.self, forKey: .mode)
        let text = try container.decodeIfPresent(String.self, forKey: .text)
        let reference = try HeistReferenceName.decodeIfPresent(
            from: container,
            forKey: .textRef,
            type: "string"
        )
        switch (text, reference) {
        case (.some(let text), nil):
            do {
                source = .text(try TextInputText(validating: text, mode: mode))
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .text,
                    in: container,
                    debugDescription: String(describing: error)
                )
            }
        case (nil, .some(let reference)):
            source = .reference(reference, mode: mode)
        case (.some, .some):
            throw DecodingError.dataCorruptedError(
                forKey: .textRef,
                in: container,
                debugDescription: "type text target accepts either text or text_ref, not both"
            )
        case (nil, nil):
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: "type text target requires text or text_ref"
            )
        }
        target = try container.decodeIfPresent(AccessibilityTarget.self, forKey: .target)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source.mode, forKey: .mode)
        switch source {
        case .text(let text):
            try container.encode(text.rawText, forKey: .text)
        case .reference(let reference, _):
            try container.encode(reference, forKey: .textRef)
        }
        try container.encodeIfPresent(target, forKey: .target)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case textRef = "text_ref"
        case mode
        case target
    }
}

extension TypeTextTarget: CustomStringConvertible {
    public var description: String {
        let sourceDescription: String
        switch source {
        case .text(let text):
            sourceDescription = CanonicalValueDescription.stringField("text", text.rawText) ?? "text=\"\""
        case .reference(let reference, _):
            sourceDescription = CanonicalValueDescription.valueField("textRef", reference) ?? "textRef=\(reference)"
        }
        return CanonicalValueDescription.call("typeText", [
            sourceDescription,
            CanonicalValueDescription.valueField("mode", source.mode),
            target?.description,
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

    /// Text to write to the pasteboard.
    public let text: PasteboardText

    public init(text: PasteboardText) {
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "pasteboard target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(PasteboardText.self, forKey: .text)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
    }
}

extension SetPasteboardTarget: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("pasteboard", [
            CanonicalValueDescription.stringField("text", text.rawText),
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
        CanonicalValueDescription.call("editAction", [
            CanonicalValueDescription.valueField("action", action),
        ].compactMap { $0 })
    }
}

package enum WaitTimeoutEnvironmentKey: String, Sendable {
    case maximum = "BUTTONHEIST_MAX_WAIT_TIMEOUT"
}

public struct WaitTimeout: Codable, Sendable, Equatable, Comparable, CustomStringConvertible,
    ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public static let defaultMaximumSeconds: Double = 60

    public static var maximumSeconds: Double {
        maximumSeconds(environment: ProcessInfo.processInfo.environment)
    }

    private let boundedSeconds: BoundedSeconds

    public init(validatingSeconds seconds: Double) throws(WaitTimeoutError) {
        try self.init(validatingSeconds: seconds, maximumSeconds: Self.maximumSeconds)
    }

    package init(
        validatingSeconds seconds: Double,
        maximumSeconds: Double
    ) throws(WaitTimeoutError) {
        do {
            self.init(boundedSeconds: try BoundedSeconds(
                value: seconds,
                maximum: maximumSeconds
            ))
        } catch let error {
            throw WaitTimeoutError.invalid(observed: error.observed, expected: error.expected)
        }
    }

    package static func maximumSeconds(environment: [String: String]) -> Double {
        guard
            let rawValue = environment[WaitTimeoutEnvironmentKey.maximum.rawValue],
            let configured = Double(rawValue),
            configured.isFinite,
            configured >= 30
        else {
            return defaultMaximumSeconds
        }
        return configured
    }

    public init(floatLiteral value: Double) {
        self = requireValidLiteralPayload {
            try Self(validatingSeconds: value)
        }
    }

    public init(integerLiteral value: Int) {
        self = requireValidLiteralPayload {
            try Self(validatingSeconds: Double(value))
        }
    }

    public static func seconds(_ value: Double) throws(WaitTimeoutError) -> Self {
        try Self(validatingSeconds: value)
    }

    public static func milliseconds(_ value: Double) throws(WaitTimeoutError) -> Self {
        try Self(validatingSeconds: value / 1_000)
    }

    public var seconds: Double { boundedSeconds.value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let seconds = try container.decode(Double.self)
        do {
            self = try Self(validatingSeconds: seconds)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(seconds)
    }

    public var description: String { CanonicalValueDescription.decimal(seconds) }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.seconds < rhs.seconds
    }

    private init(boundedSeconds: BoundedSeconds) {
        self.boundedSeconds = boundedSeconds
    }
}

public enum WaitTimeoutError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalid(observed: Double, expected: String)

    public var description: String {
        switch self {
        case .invalid(let observed, let expected):
            return "wait timeout must be \(expected) (observed \(CanonicalValueDescription.decimal(observed)))"
        }
    }
}

/// Target for the `wait` command — wait until an accessibility predicate is
/// satisfied. State predicates poll the current interface; change predicates
/// ride through intermediate settled states until the requested change is met.
public struct WaitTarget: Codable, Sendable, Equatable {
    /// The predicate to wait on.
    public let predicate: AccessibilityPredicate
    /// Optional wait duration. Omitted waits use the 30-second default; explicit
    /// values are admitted up to the configured maximum, which defaults to 60 seconds.
    public let timeout: WaitTimeout?

    public init(predicate: AccessibilityPredicate, timeout: WaitTimeout? = nil) {
        self.predicate = predicate
        self.timeout = timeout
    }

    public var resolvedTimeout: WaitTimeout { timeout ?? defaultWaitTimeout }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "wait target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        predicate = try container.decode(AccessibilityPredicate.self, forKey: .predicate)
        timeout = try container.decodeIfPresent(WaitTimeout.self, forKey: .timeout)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encodeIfPresent(timeout, forKey: .timeout)
    }

}

extension WaitTarget: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("wait", [
            predicate.description,
            timeout.map { "timeout=\(CanonicalValueDescription.decimal($0.seconds))" },
        ].compactMap { $0 })
    }
}
