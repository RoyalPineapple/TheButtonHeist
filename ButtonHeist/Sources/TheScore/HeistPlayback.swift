import Foundation

// MARK: - Heist Playback

/// A recorded session that can be played back against the same (or similar) app.
/// This is the `.heist` persistence model. Runtime playback should bind these
/// wire fields to typed commands before execution.
public struct HeistPlayback: Codable, Sendable, Equatable {
    /// Format version. Increment when the step schema changes.
    public static let currentVersion = 4

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

/// A single command in a heist playback. Contains the command name, durable
/// matcher target, command-specific arguments, and optional recording metadata.
///
/// Element identity lives under `target`; command arguments live under
/// `arguments`. Top-level step fields are closed so unsupported shapes fail at
/// the playback boundary.
public struct HeistEvidence: Codable, Sendable, Equatable {
    /// The `TheFence.Command` raw value (e.g. `"activate"`, `"type_text"`,
    /// `"swipe"`). Stored as a string rather than the enum because `Command`
    /// lives in TheButtonHeist (iOS-only) and TheScore must be portable across
    /// iOS + macOS.
    public let command: String
    /// Durable replay target — nil means the command doesn't target an element.
    /// A persisted heist target must be a matcher; capture-local heistIds live
    /// under `_recorded.heistId` as evidence only.
    public let target: ElementTarget?
    /// Command-specific arguments (direction, text, duration, etc.).
    /// Excludes command name and element targeting fields.
    public let arguments: [String: HeistValue]
    /// Recording-time metadata for debugging. Not used during playback.
    public let recorded: RecordedMetadata?

    public init(
        command: String,
        target: ElementTarget? = nil,
        arguments: [String: HeistValue] = [:],
        recorded: RecordedMetadata? = nil
    ) throws {
        try Self.validateDurableTarget(target)
        self.command = command
        self.target = target
        self.arguments = arguments
        self.recorded = recorded
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command, target, arguments
        case recorded = "_recorded"
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownStepKeys(decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        target = try Self.decodeDurableTarget(from: container, forKey: .target)
        arguments = try container.decodeIfPresent([String: HeistValue].self, forKey: .arguments) ?? [:]
        recorded = try container.decodeIfPresent(RecordedMetadata.self, forKey: .recorded)
    }

    private static func rejectUnknownStepKeys(_ decoder: Decoder) throws {
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [unknownKey],
            debugDescription: "Unknown heist playback step field \"\(unknownKey.stringValue)\""
        ))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try encodeDurableTarget(to: &container)
        if !arguments.isEmpty {
            try container.encode(arguments, forKey: .arguments)
        }
        try container.encodeIfPresent(recorded, forKey: .recorded)
    }

    private static func decodeDurableTarget(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> ElementTarget? {
        guard let target = try container.decodeIfPresent(ElementTarget.self, forKey: key) else {
            return nil
        }
        do {
            try validateDurableTarget(target)
            return target
        } catch HeistEvidenceError.captureHandleTarget {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "HeistEvidence target requires matcher fields; heistId is capture-local evidence under _recorded.heistId"
            )
        } catch HeistEvidenceError.emptyMatcherTarget {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "HeistEvidence target requires at least one matcher field"
            )
        } catch {
            throw error
        }
    }

    private static func validateDurableTarget(_ target: ElementTarget?) throws {
        switch target {
        case nil:
            return
        case .matcher(let matcher, _) where matcher.hasPredicates:
            return
        case .matcher:
            throw HeistEvidenceError.emptyMatcherTarget
        case .heistId:
            throw HeistEvidenceError.captureHandleTarget
        }
    }

    private func encodeDurableTarget(to container: inout KeyedEncodingContainer<CodingKeys>) throws {
        guard let target else { return }
        switch target {
        case .matcher(let matcher, _) where matcher.hasPredicates:
            try container.encode(target, forKey: .target)
        case .matcher:
            throw EncodingError.invalidValue(target, .init(
                codingPath: container.codingPath + [CodingKeys.target],
                debugDescription: "HeistEvidence target requires at least one matcher field"
            ))
        case .heistId:
            throw EncodingError.invalidValue(target, .init(
                codingPath: container.codingPath + [CodingKeys.target],
                debugDescription: "HeistEvidence target requires matcher fields; heistId is capture-local evidence under _recorded.heistId"
            ))
        }
    }

}

public enum HeistEvidenceError: Error, Sendable, Equatable {
    case captureHandleTarget
    case emptyMatcherTarget
}

extension HeistEvidence: CustomStringConvertible {
    public var description: String {
        let argumentSummary = arguments.isEmpty ? nil : "args=\(ScoreDescription.call("arguments", argumentsDescriptionFields))"
        return ScoreDescription.call("step", [
            ScoreDescription.stringField("command", command),
            target?.description,
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

/// A JSON-encodable value type for typed command arguments.
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
