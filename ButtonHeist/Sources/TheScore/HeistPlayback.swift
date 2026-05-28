import Foundation

// MARK: - Heist Playback

/// A recorded session that can be played back against the same (or similar) app.
/// This is the `.heist` persistence model. Runtime playback should bind these
/// wire fields to typed commands before execution.
public struct HeistPlayback: Codable, Sendable, Equatable {
    /// Format version. Increment when the step schema changes.
    public static let currentVersion = 2

    /// Current heist file format version.
    public let version: Int
    /// ISO 8601 timestamp of when the recording was made.
    public let recorded: Date
    /// Bundle identifier of the app that was running during recording.
    public let app: String
    /// Ordered list of commands to replay.
    public let steps: [HeistEvidence]

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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case recorded
        case app
        case steps
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownPlaybackKeys(decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported heist file version \(decodedVersion). " +
                    "This Button Heist build supports version \(Self.currentVersion). " +
                    "Re-record the heist with the current format."
            )
        }

        version = decodedVersion
        recorded = try container.decode(Date.self, forKey: .recorded)
        app = try container.decode(String.self, forKey: .app)
        steps = try container.decode([HeistEvidence].self, forKey: .steps)
    }

    private static func rejectUnknownPlaybackKeys(_ decoder: Decoder) throws {
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [unknownKey],
            debugDescription: "Unknown heist playback field \"\(unknownKey.stringValue)\""
        ))
    }
}

extension HeistPlayback: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("heist", [
            ScoreDescription.valueField("version", version),
            ScoreDescription.stringField("app", app),
            "steps=\(steps.count)",
        ].compactMap { $0 })
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
    /// Ordinal only disambiguates a non-empty matcher.
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
    private static let forbiddenArgumentKeys: Set<String> = ["heistId"]

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
        let decodedOrdinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if let decodedOrdinal, decodedOrdinal < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: "ordinal must be non-negative, got \(decodedOrdinal)"
            )
        }
        ordinal = decodedOrdinal
        if decodedOrdinal != nil, matcher.nonEmpty == nil {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: "ordinal only disambiguates matcher results; playback steps require matcher fields"
            )
        }
        target = matcher.nonEmpty

        recorded = try container.decodeIfPresent(RecordedMetadata.self, forKey: .recorded)

        // Everything else in the flat object is a command argument.
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var extraArguments: [String: HeistValue] = [:]
        for key in dynamicContainer.allKeys {
            guard !Self.reservedKeys.contains(key.stringValue) else { continue }
            if Self.forbiddenArgumentKeys.contains(key.stringValue) {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: """
                    Heist playback step must not contain top-level heistId; use matcher fields for durable \
                    playback identity and _recorded.heistId for metadata
                    """
                ))
            }
            extraArguments[key.stringValue] = try dynamicContainer.decode(
                HeistValue.self, forKey: key
            )
        }
        arguments = extraArguments
    }

    public func encode(to encoder: Encoder) throws {
        if let forbiddenKey = arguments.keys.sorted().first(where: { Self.forbiddenArgumentKeys.contains($0) }) {
            throw EncodingError.invalidValue(arguments, .init(
                codingPath: encoder.codingPath + [DynamicCodingKey(stringValue: forbiddenKey)],
                debugDescription: """
                Heist playback step must not contain top-level \(forbiddenKey); use matcher fields for durable \
                playback identity and _recorded.heistId for metadata
                """
            ))
        }
        if target?.heistId != nil {
            throw EncodingError.invalidValue(target as Any, .init(
                codingPath: encoder.codingPath + [DynamicCodingKey(stringValue: "heistId")],
                debugDescription: """
                Heist playback target matcher must not contain heistId; use matcher fields for durable \
                playback identity and _recorded.heistId for metadata
                """
            ))
        }
        if ordinal != nil, target?.nonEmpty == nil {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath + [DynamicCodingKey(stringValue: "ordinal")],
                debugDescription: "ordinal only disambiguates matcher results; playback steps require matcher fields"
            ))
        }

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

}

extension HeistEvidence: CustomStringConvertible {
    public var description: String {
        let argumentSummary = arguments.isEmpty ? nil : "args=\(ScoreDescription.call("arguments", argumentsDescriptionFields))"
        return ScoreDescription.call("step", [
            ScoreDescription.stringField("command", command),
            target?.description,
            ScoreDescription.valueField("ordinal", ordinal),
            argumentSummary,
            recorded?.description,
        ].compactMap { $0 })
    }

    private var argumentsDescriptionFields: [String] {
        arguments
            .sorted { $0.key < $1.key }
            .map { "\(ScoreDescription.quoted($0.key))=\($0.value)" }
    }
}

// MARK: - Heist Value

/// A JSON-encodable value type for command arguments.
/// Supports the value types that TheFence.execute(request:) expects.
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
            return ScoreDescription.quoted(stringValue)
        case .int(let intValue):
            return "\(intValue)"
        case .double(let doubleValue):
            return ScoreDescription.decimal(doubleValue)
        case .bool(let boolValue):
            return "\(boolValue)"
        case .array(let arrayValue):
            return "[\(arrayValue.map(\.description).joined(separator: ", "))]"
        case .object(let objectValue):
            let fields = objectValue
                .sorted { $0.key < $1.key }
                .map { "\(ScoreDescription.quoted($0.key))=\($0.value)" }
            return "{\(fields.joined(separator: ", "))}"
        }
    }
}

// MARK: - Recorded Metadata

/// Debugging metadata captured at recording time. Preserved in the `.heist` file
/// under the `_recorded` key but ignored during playback.
public struct RecordedMetadata: Codable, Sendable, Equatable {
    /// The heistId that was used to target the element at recording time.
    public let heistId: HeistId?
    /// The element's frame at recording time.
    public let frame: RecordedFrame?
    /// Whether the step used coordinate-only targeting (no element).
    public let coordinateOnly: Bool?
    /// Accessibility trace observed while recording.
    public let accessibilityTrace: AccessibilityTrace?
    /// Expectation evidence observed while recording. Playback ignores this.
    public let expectation: ExpectationResult?
    /// Compact accessibility delta projection derived from the recorded trace.
    public var accessibilityDelta: AccessibilityTrace.Delta? {
        accessibilityTrace?.endpointDeltaProjection
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case heistId
        case frame
        case coordinateOnly
        case accessibilityTrace
        case expectation
    }

    public init(
        heistId: HeistId? = nil,
        frame: RecordedFrame? = nil,
        coordinateOnly: Bool? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.heistId = heistId
        self.frame = frame
        self.coordinateOnly = coordinateOnly
        self.accessibilityTrace = accessibilityTrace
        self.expectation = expectation
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownMetadataKeys(decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            heistId: try container.decodeIfPresent(HeistId.self, forKey: .heistId),
            frame: try container.decodeIfPresent(RecordedFrame.self, forKey: .frame),
            coordinateOnly: try container.decodeIfPresent(Bool.self, forKey: .coordinateOnly),
            accessibilityTrace: try container.decodeIfPresent(AccessibilityTrace.self, forKey: .accessibilityTrace),
            expectation: try container.decodeIfPresent(ExpectationResult.self, forKey: .expectation)
        )
    }

    private static func rejectUnknownMetadataKeys(_ decoder: Decoder) throws {
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [unknownKey],
            debugDescription: "Unknown recorded metadata field \"\(unknownKey.stringValue)\""
        ))
    }
}

extension RecordedMetadata: CustomStringConvertible {
    public var description: String {
        let traceReceiptCount = accessibilityTrace?.receipts.count
        return ScoreDescription.call("recorded", [
            ScoreDescription.stringField("heistId", heistId),
            frame?.description,
            ScoreDescription.valueField("coordinateOnly", coordinateOnly),
            traceReceiptCount.map { "traceReceipts=\($0)" },
            expectation?.description,
        ].compactMap { $0 })
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

extension RecordedFrame: CustomStringConvertible {
    public var description: String {
        "frame(\(ScoreDescription.decimal(x)),\(ScoreDescription.decimal(y)),\(ScoreDescription.decimal(width)),\(ScoreDescription.decimal(height)))"
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
