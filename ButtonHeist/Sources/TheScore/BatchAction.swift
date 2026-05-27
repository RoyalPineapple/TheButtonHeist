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

/// One command in an ordered batch plan.
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

    private enum CommandCodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let commandHeader = try container.nestedContainer(keyedBy: CommandCodingKeys.self, forKey: .command)
        let commandType = try commandHeader.decode(ClientWireMessageType.self, forKey: .type)
        guard commandType != .batchExecutionPlan else {
            throw DecodingError.dataCorruptedError(
                forKey: .command,
                in: container,
                debugDescription: "BatchStep command \"\(commandType.rawValue)\" cannot be a nested batch execution plan"
            )
        }
        let command = try container.decode(ClientMessage.self, forKey: .command)
        guard !command.isNestedBatchExecutionPlan else {
            throw DecodingError.dataCorruptedError(
                forKey: .command,
                in: container,
                debugDescription: "BatchStep command \"\(command.canonicalName)\" cannot be a nested batch execution plan"
            )
        }
        self.init(
            command: command,
            expectation: try container.decode(ActionExpectation.self, forKey: .expect),
            deadline: try container.decode(Deadline.self, forKey: .deadline)
        )
    }

    public func encode(to encoder: Encoder) throws {
        guard !command.isNestedBatchExecutionPlan else {
            throw EncodingError.invalidValue(command, .init(
                codingPath: encoder.codingPath,
                debugDescription: "BatchStep command \"\(command.canonicalName)\" cannot be a nested batch execution plan"
            ))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encode(expectation, forKey: .expect)
        try container.encode(deadline, forKey: .deadline)
    }
}

extension ClientMessage {
    fileprivate var isNestedBatchExecutionPlan: Bool {
        if case .batchExecutionPlan = self {
            return true
        }
        return false
    }

    public var fulfillsOwnBatchExpectation: Bool {
        switch self {
        case .waitFor, .waitForChange:
            return true
        default:
            return false
        }
    }
}
