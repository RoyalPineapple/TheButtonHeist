import Foundation

// MARK: - Heist Playback

/// A recorded session that can be played back against the same (or similar) app.
/// Each step is a command dictionary compatible with TheFence.execute(request:),
/// with element targets expressed as ElementMatcher fields — never heistIds.
public struct HeistPlayback: Codable, Sendable, Equatable {
    /// Format version. Increment when the step schema changes.
    public static let currentVersion = 2

    /// Version from the decoded file. Not enforced at decode time — a playback
    /// with `version: 99` decodes cleanly; callers that care must compare
    /// against `HeistPlayback.currentVersion` before replay.
    public let version: Int
    /// ISO 8601 timestamp of when the recording was made.
    public let recorded: Date
    /// Bundle identifier of the app that was running during recording.
    public let app: String
    /// Ordered list of commands to replay.
    public var steps: [HeistEvidence]

    public init(
        version: Int = HeistPlayback.currentVersion,
        recorded: Date = Date(),
        app: String,
        steps: [HeistEvidence] = []
    ) {
        self.version = version
        self.recorded = recorded
        self.app = app
        self.steps = steps
    }
}

// MARK: - Heist Step

/// A single command in a heist playback. Contains the command name, matcher-based
/// element targeting fields, command-specific arguments, and optional recording metadata.
///
/// The step is structured so that dropping `_recorded` yields a valid
/// TheFence.execute(request:) dictionary — matcher fields sit at the top level
/// alongside command-specific args, exactly as TheFence expects.
public struct HeistEvidence: Codable, Sendable, Equatable {
    /// The `TheFence.Command` raw value (e.g. `"activate"`, `"type_text"`,
    /// `"swipe"`). Stored as a string rather than the enum because `Command`
    /// lives in TheButtonHeist (iOS-only) and TheScore must be portable across
    /// iOS + macOS.
    public let command: String
    /// Element matcher fields — nil means the command doesn't target an element.
    public let target: ElementMatcher?
    /// 0-based selection index when the matcher is ambiguous (multiple elements
    /// share the same label/traits). Nil when the matcher uniquely identifies the element.
    public let ordinal: Int?
    /// Command-specific arguments (direction, text, duration, etc.).
    /// Excludes command name and element targeting fields.
    public let arguments: [String: HeistValue]
    /// Recording-time metadata for debugging. Not used during playback.
    public let recorded: RecordedMetadata?

    public init(
        command: String,
        target: ElementMatcher? = nil,
        ordinal: Int? = nil,
        arguments: [String: HeistValue] = [:],
        recorded: RecordedMetadata? = nil
    ) {
        self.command = command
        self.target = target
        self.ordinal = ordinal
        self.arguments = arguments
        self.recorded = recorded
    }

    // MARK: - Codable (flat wire format)

    private enum CodingKeys: String, CodingKey {
        case command
        case label, identifier, value, traits, excludeTraits
        case ordinal
        case recorded = "_recorded"
    }

    /// Keys that belong to element targeting or step metadata, not command arguments.
    private static let reservedKeys: Set<String> = [
        "command", "label", "identifier", "value", "traits", "excludeTraits", "ordinal", "_recorded",
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)

        let matcher = ElementMatcher(
            label: try container.decodeIfPresent(String.self, forKey: .label),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            value: try container.decodeIfPresent(String.self, forKey: .value),
            traits: try container.decodeIfPresent([HeistTrait].self, forKey: .traits),
            excludeTraits: try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits)
        )
        target = matcher.nonEmpty
        ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)

        recorded = try container.decodeIfPresent(RecordedMetadata.self, forKey: .recorded)

        // Everything else in the flat object is a command argument.
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var extraArguments: [String: HeistValue] = [:]
        for key in dynamicContainer.allKeys {
            guard !Self.reservedKeys.contains(key.stringValue) else { continue }
            extraArguments[key.stringValue] = try dynamicContainer.decode(
                HeistValue.self, forKey: key
            )
        }
        arguments = extraArguments
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)

        if let target {
            try container.encodeIfPresent(target.label, forKey: .label)
            try container.encodeIfPresent(target.identifier, forKey: .identifier)
            try container.encodeIfPresent(target.value, forKey: .value)
            try container.encodeIfPresent(target.traits, forKey: .traits)
            try container.encodeIfPresent(target.excludeTraits, forKey: .excludeTraits)
        }
        try container.encodeIfPresent(ordinal, forKey: .ordinal)

        try container.encodeIfPresent(recorded, forKey: .recorded)

        // Encode extra arguments as flat top-level keys.
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, playbackValue) in arguments.sorted(by: { $0.key < $1.key }) {
            try dynamicContainer.encode(playbackValue, forKey: DynamicCodingKey(stringValue: key))
        }
    }

    /// Convert this step to a TheFence-compatible request dictionary for execution.
    public func toRequestDictionary() -> [String: Any] {
        var dictionary: [String: Any] = ["command": command]

        if let target {
            if let label = target.label { dictionary["label"] = label }
            if let matchIdentifier = target.identifier { dictionary["identifier"] = matchIdentifier }
            if let matchValue = target.value { dictionary["value"] = matchValue }
            if let matchTraits = target.traits { dictionary["traits"] = matchTraits.map(\.rawValue) }
            if let matchExclude = target.excludeTraits { dictionary["excludeTraits"] = matchExclude.map(\.rawValue) }
        }
        if let ordinal { dictionary["ordinal"] = ordinal }

        for (key, playbackValue) in arguments {
            dictionary[key] = playbackValue.toAny()
        }

        return dictionary
    }

    /// Build a scroll_to_visible request from this step's element matcher.
    /// Used by the playback engine to scroll off-screen elements into view before retrying.
    public func scrollToVisibleRequest() -> [String: Any] {
        var request: [String: Any] = ["command": "scroll_to_visible"]
        if let target {
            if let label = target.label { request["label"] = label }
            if let matchIdentifier = target.identifier { request["identifier"] = matchIdentifier }
            if let matchValue = target.value { request["value"] = matchValue }
            if let matchTraits = target.traits { request["traits"] = matchTraits.map(\.rawValue) }
            if let matchExclude = target.excludeTraits { request["excludeTraits"] = matchExclude.map(\.rawValue) }
        }
        if let ordinal { request["ordinal"] = ordinal }
        return request
    }
}

// MARK: - Heist Value

/// A JSON-compatible value type for command arguments.
/// Supports the value types that TheFence.execute(request:) expects.
public enum HeistValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([HeistValue])
    case object([String: HeistValue])

    public init(from decoder: Decoder) throws {
        // Documented exception to the "no `try?` in production" rule:
        // `HeistValue` is an any-JSON type and must probe six decoder
        // shapes to discriminate between them. The discarded errors are
        // always "wrong type, try the next one"; a semantic decode error
        // fires as the `DecodingError.dataCorrupted` below. Every
        // alternative (hand-rolled tokenizer, `JSONSerialization` round
        // trip, nested keyed containers) is strictly worse for this
        // shape.
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

    /// Convert to an untyped `Any` for passing to TheFence.execute(request:).
    public func toAny() -> Any {
        switch self {
        case .string(let stringValue): return stringValue
        case .int(let intValue): return intValue
        case .double(let doubleValue): return doubleValue
        case .bool(let boolValue): return boolValue
        case .array(let arrayValue): return arrayValue.map { $0.toAny() }
        case .object(let objectValue): return objectValue.mapValues { $0.toAny() }
        }
    }

    /// Create from an untyped value. Returns nil for unsupported types.
    public static func from(_ value: Any) -> HeistValue? {
        switch value {
        case let boolValue as Bool: return .bool(boolValue)
        case let intValue as Int: return .int(intValue)
        case let doubleValue as Double: return .double(doubleValue)
        case let stringValue as String: return .string(stringValue)
        case let arrayValue as [Any]:
            var converted: [HeistValue] = []
            for element in arrayValue {
                guard let heistValue = from(element) else { return nil }
                converted.append(heistValue)
            }
            return .array(converted)
        case let objectValue as [String: Any]:
            var result: [String: HeistValue] = [:]
            for (key, nestedValue) in objectValue {
                guard let converted = from(nestedValue) else { return nil }
                result[key] = converted
            }
            return .object(result)
        default:
            return nil
        }
    }
}

// MARK: - Recorded Metadata

/// Debugging metadata captured at recording time. Preserved in the `.heist` file
/// under the `_recorded` key but ignored during playback.
public struct RecordedMetadata: Codable, Sendable, Equatable {
    /// The heistId that was used to target the element at recording time.
    public let heistId: String?
    /// The element's frame at recording time.
    public let frame: RecordedFrame?
    /// Whether the step used coordinate-only targeting (no element).
    public let coordinateOnly: Bool?
    /// Accessibility trace observed while recording.
    public let accessibilityTrace: AccessibilityTrace?
    /// Compact accessibility delta observed while recording.
    public let accessibilityDelta: AccessibilityTrace.Delta?
    /// Why the recorder could not produce a unique semantic matcher from the trace capture.
    public let matcherFallbackReason: String?
    /// Expectation evidence observed while recording. Playback ignores this.
    public let expectation: ExpectationResult?

    public init(
        heistId: String? = nil,
        frame: RecordedFrame? = nil,
        coordinateOnly: Bool? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        accessibilityDelta: AccessibilityTrace.Delta? = nil,
        matcherFallbackReason: String? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.heistId = heistId
        self.frame = frame
        self.coordinateOnly = coordinateOnly
        self.accessibilityTrace = accessibilityTrace
        self.accessibilityDelta = accessibilityDelta
        self.matcherFallbackReason = matcherFallbackReason
        self.expectation = expectation
    }
}

/// Frame captured at recording time for debugging and visual alignment.
public struct RecordedFrame: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Dynamic Coding Key

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
