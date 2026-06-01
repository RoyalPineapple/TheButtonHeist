import Foundation

// MARK: - Heist Plan

/// Canonical ordered automation contract.
///
/// Swift DSL source, dynamic agent JSON, recordings, and playback all converge
/// on this value. The Swift DSL itself is future work; `HeistPlan` is the
/// product contract.
public struct HeistPlan: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public let version: Int
    public let steps: [HeistStep]

    public init(
        version: Int = HeistPlan.currentVersion,
        steps: [HeistStep]
    ) {
        self.version = version
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, steps
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist plan")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported heist plan version \(decodedVersion). " +
                    "This Button Heist build supports version \(Self.currentVersion)."
            )
        }
        version = decodedVersion
        steps = try container.decode([HeistStep].self, forKey: .steps)
        guard !steps.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .steps,
                in: container,
                debugDescription: "HeistPlan requires at least one step"
            )
        }
    }
}

extension HeistPlan: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("heistPlan", [
            ScoreDescription.valueField("version", version),
            "steps=\(steps.count)",
        ].compactMap { $0 })
    }
}

// MARK: - Heist Step

public enum HeistStep: Codable, Sendable, Equatable {
    case action(ActionStep)
    case wait(WaitStep)
    case warn(WarnStep)
    case fail(FailStep)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, action, wait, warn, fail
    }

    private enum StepType: String, Codable {
        case action, wait, warn, fail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        switch type {
        case .action:
            try decoder.rejectUnknownKeys(allowed: ["type", "action"], typeName: "action heist step")
            self = .action(try container.decode(ActionStep.self, forKey: .action))
        case .wait:
            try decoder.rejectUnknownKeys(allowed: ["type", "wait"], typeName: "wait heist step")
            self = .wait(try container.decode(WaitStep.self, forKey: .wait))
        case .warn:
            try decoder.rejectUnknownKeys(allowed: ["type", "warn"], typeName: "warn heist step")
            self = .warn(try container.decode(WarnStep.self, forKey: .warn))
        case .fail:
            try decoder.rejectUnknownKeys(allowed: ["type", "fail"], typeName: "fail heist step")
            self = .fail(try container.decode(FailStep.self, forKey: .fail))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let step):
            try container.encode(StepType.action, forKey: .type)
            try container.encode(step, forKey: .action)
        case .wait(let step):
            try container.encode(StepType.wait, forKey: .type)
            try container.encode(step, forKey: .wait)
        case .warn(let step):
            try container.encode(StepType.warn, forKey: .type)
            try container.encode(step, forKey: .warn)
        case .fail(let step):
            try container.encode(StepType.fail, forKey: .type)
            try container.encode(step, forKey: .fail)
        }
    }
}

extension HeistStep: CustomStringConvertible {
    public var description: String {
        switch self {
        case .action(let step): return step.description
        case .wait(let step): return step.description
        case .warn(let step): return step.description
        case .fail(let step): return step.description
        }
    }
}

// MARK: - Step Payloads

public struct ActionStep: Codable, Sendable, Equatable {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(command: ClientMessage, expectation: WaitStep? = nil) throws {
        guard command.isHeistActionCommand else {
            throw HeistPlanError.unsupportedActionCommand(command.wireType.rawValue)
        }
        self.command = command
        self.expectation = expectation
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command, expectation
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "action step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            command: try container.decode(ClientMessage.self, forKey: .command),
            expectation: try container.decodeIfPresent(WaitStep.self, forKey: .expectation)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(expectation, forKey: .expectation)
    }
}

extension ActionStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("action", [
            "command=\(command.wireType.rawValue)",
            expectation.map { "expect=\($0)" },
        ].compactMap { $0 })
    }
}

public struct WaitStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
    }

    public let predicate: AccessibilityPredicate
    /// Seconds. `0` means immediate predicate evaluation.
    public let timeout: Double

    public init(predicate: AccessibilityPredicate, timeout: Double = 0) {
        self.predicate = predicate
        self.timeout = timeout
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "wait step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
            timeout: try container.decode(Double.self, forKey: .timeout)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(timeout, forKey: .timeout)
    }
}

extension WaitStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("wait", [
            predicate.description,
            "timeout=\(ScoreDescription.decimal(timeout))",
        ])
    }
}

public struct WarnStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case message
    }

    public let message: String

    public init(message: String) {
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "warn step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(message: try container.decode(String.self, forKey: .message))
    }
}

extension WarnStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("warn", [ScoreDescription.quoted(message)])
    }
}

public struct FailStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case message
    }

    public let message: String

    public init(message: String) {
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "fail step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(message: try container.decode(String.self, forKey: .message))
    }
}

public enum HeistPlanError: Error, Sendable, Equatable {
    case unsupportedActionCommand(String)
}

public extension ClientMessage {
    var isHeistActionCommand: Bool {
        switch self {
        case .activate, .increment, .decrement, .performCustomAction, .rotor,
             .oneFingerTap, .longPress, .swipe, .drag, .typeText, .editAction,
             .setPasteboard, .scroll, .scrollToVisible, .elementSearch,
             .scrollToEdge, .resignFirstResponder:
            return true
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .getPasteboard, .requestScreen, .wait, .heistPlan:
            return false
        }
    }
}

extension FailStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("fail", [ScoreDescription.quoted(message)])
    }
}
