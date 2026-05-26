import Foundation

/// Per-operation execution deadline. The timeout may be omitted when execution
/// should use the receiver's default action timeout.
public struct Deadline: Codable, Sendable, Equatable {
    public let timeout: Double?

    public init(timeout: Double? = nil) {
        self.timeout = timeout
    }
}

extension Deadline: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("deadline", [
            timeout.map { "timeout=\(ScoreDescription.decimal($0))" },
        ].compactMap { $0 })
    }
}

/// One executable non-read command in a batch plan.
public struct BatchStep: Sendable {
    public let command: ClientMessage
    public let expectation: ActionExpectation
    public let deadline: Deadline

    public init(
        command: ClientMessage,
        expectation: ActionExpectation,
        deadline: Deadline
    ) {
        self.command = command
        self.expectation = expectation
        self.deadline = deadline
    }

    public static func command(
        _ command: ClientMessage,
        expect expectation: ActionExpectation? = nil,
        deadline: Deadline? = nil
    ) -> BatchStep {
        BatchStep(
            command: command,
            expectation: expectation ?? command.defaultBatchExpectation,
            deadline: deadline ?? command.defaultBatchDeadline
        )
    }
}

extension BatchStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("step", [
            "command=\(command.canonicalName)",
            "expect=\(expectation)",
            "deadline=\(deadline)",
        ])
    }
}

extension BatchStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case command, expect, deadline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let command = try container.decode(ClientMessage.self, forKey: .command)
        guard command.isBatchExecutableCommand else {
            throw DecodingError.dataCorruptedError(
                forKey: .command,
                in: container,
                debugDescription: "BatchStep command \"\(command.canonicalName)\" is not batch-executable"
            )
        }
        self.init(
            command: command,
            expectation: try container.decodeIfPresent(ActionExpectation.self, forKey: .expect)
                ?? command.defaultBatchExpectation,
            deadline: try container.decodeIfPresent(Deadline.self, forKey: .deadline)
                ?? command.defaultBatchDeadline
        )
    }

    public func encode(to encoder: Encoder) throws {
        guard command.isBatchExecutableCommand else {
            throw EncodingError.invalidValue(command, .init(
                codingPath: encoder.codingPath,
                debugDescription: "BatchStep command \"\(command.canonicalName)\" is not batch-executable"
            ))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(expectation, forKey: .expect)
        try container.encode(deadline, forKey: .deadline)
    }
}

extension ClientMessage {
    public var isBatchExecutableCommand: Bool {
        switch self {
        case .activate,
             .increment,
             .decrement,
             .performCustomAction,
             .rotor,
             .touchTap,
             .touchLongPress,
             .touchSwipe,
             .touchDrag,
             .touchPinch,
             .touchRotate,
             .touchTwoFingerTap,
             .touchDrawPath,
             .touchDrawBezier,
             .typeText,
             .editAction,
             .setPasteboard,
             .scroll,
             .scrollToVisible,
             .elementSearch,
             .scrollToEdge,
             .waitForIdle,
             .waitFor,
             .waitForChange,
             .explore,
             .resignFirstResponder:
            return true
        case .clientHello,
             .authenticate,
             .requestInterface,
             .ping,
             .status,
             .getPasteboard,
             .batchExecutionPlan,
             .requestScreen,
             .startRecording,
             .stopRecording:
            return false
        }
    }

    public var fulfillsOwnBatchExpectation: Bool {
        switch self {
        case .waitFor, .waitForChange:
            return true
        default:
            return false
        }
    }

    public var defaultBatchExpectation: ActionExpectation {
        switch self {
        case .waitFor(let target):
            return target.resolvedAbsent
                ? .elementDisappeared(target.elementTarget.expectationMatcher)
                : .elementAppeared(target.elementTarget.expectationMatcher)
        case .waitForChange(let target):
            return target.expect ?? .screenChanged
        default:
            return .delivery
        }
    }

    public var defaultBatchDeadline: Deadline {
        switch self {
        case .waitForIdle(let target):
            return Deadline(timeout: target.timeout ?? 5)
        case .waitFor(let target):
            return Deadline(timeout: target.resolvedTimeout)
        case .waitForChange(let target):
            return Deadline(timeout: target.resolvedTimeout)
        default:
            return Deadline()
        }
    }
}

private extension ElementTarget {
    var expectationMatcher: ElementMatcher {
        switch self {
        case .heistId(let heistId):
            return ElementMatcher(heistId: heistId)
        case .matcher(let matcher, _):
            return matcher
        }
    }
}
