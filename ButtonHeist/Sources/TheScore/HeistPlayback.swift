import Foundation

// MARK: - Heist Playback

/// A deterministic heist contract that can be played back against the same (or
/// similar) app. Runtime playback binds these wire fields to typed commands
/// before execution.
public struct HeistPlayback: Codable, Sendable, Equatable {
    /// Format version. Increment when the step schema changes.
    public static let currentVersion = 6

    /// Current heist file format version.
    public let version: Int
    /// Bundle identifier of the app that was running during recording.
    public let app: String
    /// Ordered list of commands to replay.
    public let steps: [HeistStep]

    public init(
        version: Int = HeistPlayback.currentVersion,
        app: String,
        steps: [HeistStep] = []
    ) {
        self.version = version
        self.app = app
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case app
        case steps
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist playback")
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
        app = try container.decode(String.self, forKey: .app)
        steps = try container.decode([HeistStep].self, forKey: .steps)
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
/// matcher target, command-specific arguments, and optional semantic
/// expectation.
///
/// Element identity lives under `target`; command arguments live under
/// `arguments`. Top-level step fields are closed so unsupported shapes fail at
/// the playback boundary.
public struct HeistStep: Codable, Sendable, Equatable {
    /// The `TheFence.Command` raw value (e.g. `"activate"`, `"type_text"`,
    /// `"swipe"`). Stored as a string rather than the enum because `Command`
    /// lives in TheButtonHeist (iOS-only) and TheScore must be portable across
    /// iOS + macOS.
    public let command: String
    /// Durable replay target — nil means the command doesn't target an element.
    /// A persisted heist target must be a matcher; capture-local heistIds are
    /// resolved before the step is written.
    public let target: ElementTarget?
    /// Command-specific arguments (direction, text, duration, etc.).
    /// Excludes command name and element targeting fields.
    public let arguments: [String: HeistValue]
    /// Semantic outcome expected after the command executes.
    public let expectation: ActionExpectation?

    public init(
        command: String,
        target: ElementTarget? = nil,
        arguments: [String: HeistValue] = [:],
        expectation: ActionExpectation? = nil
    ) throws {
        try Self.validateDurableTarget(target)
        self.command = command
        self.target = target
        self.arguments = arguments
        self.expectation = expectation
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command, target, arguments, expectation
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist playback step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        target = try Self.decodeDurableTarget(from: container, forKey: .target)
        arguments = try container.decodeIfPresent([String: HeistValue].self, forKey: .arguments) ?? [:]
        expectation = try container.decodeIfPresent(ActionExpectation.self, forKey: .expectation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try encodeDurableTarget(to: &container)
        if !arguments.isEmpty {
            try container.encode(arguments, forKey: .arguments)
        }
        try container.encodeIfPresent(expectation, forKey: .expectation)
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
        } catch HeistStepError.captureHandleTarget {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "HeistStep target requires matcher fields; heistId is a capture-local handle"
            )
        } catch HeistStepError.emptyMatcherTarget {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "HeistStep target requires at least one matcher field"
            )
        }
    }

    private static func validateDurableTarget(_ target: ElementTarget?) throws {
        switch target {
        case nil:
            return
        case .matcher(let matcher, _) where matcher.hasPredicates:
            return
        case .matcher:
            throw HeistStepError.emptyMatcherTarget
        case .heistId:
            throw HeistStepError.captureHandleTarget
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
                debugDescription: "HeistStep target requires at least one matcher field"
            ))
        case .heistId:
            throw EncodingError.invalidValue(target, .init(
                codingPath: container.codingPath + [CodingKeys.target],
                debugDescription: "HeistStep target requires matcher fields; heistId is a capture-local handle"
            ))
        }
    }

}

public enum HeistStepError: Error, Sendable, Equatable {
    case captureHandleTarget
    case emptyMatcherTarget
}

extension HeistStep: CustomStringConvertible {
    public var description: String {
        let argumentSummary = arguments.isEmpty ? nil : "args=\(ScoreDescription.call("arguments", argumentsDescriptionFields))"
        let expectationSummary = expectation.map { _ in "expectation" }
        return ScoreDescription.call("step", [
            ScoreDescription.stringField("command", command),
            target?.description,
            argumentSummary,
            expectationSummary,
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
