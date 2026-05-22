import Foundation

// MARK: - Batch Execution Plan

/// Policy for executing an InsideJob-owned typed batch plan.
public enum BatchExecutionPolicy: String, Codable, CaseIterable, Sendable {
    case stopOnError = "stop_on_error"
    case continueOnError = "continue_on_error"
}

extension BatchExecutionPolicy: CustomStringConvertible {
    public var description: String { rawValue }
}

/// A typed batch execution plan for InsideJob.
///
/// This is intentionally a domain model, not a list of public command
/// dictionaries. Element identity in batch targets is semantic: `sourceHeistId`
/// records where the target came from, while `matcher`/`ordinal` are the
/// executable selector.
public struct BatchPlan: Sendable {
    public let steps: [BatchStep]
    public let policy: BatchExecutionPolicy

    public init(
        steps: [BatchStep],
        policy: BatchExecutionPolicy = .stopOnError
    ) {
        self.steps = steps
        self.policy = policy
    }
}

extension BatchPlan: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("batchExecutionPlan", [
            ScoreDescription.valueField("policy", policy),
            "steps=\(steps.count)",
        ].compactMap { $0 })
    }
}

extension BatchPlan: Codable {
    private enum CodingKeys: String, CodingKey {
        case steps, policy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decode([BatchStep].self, forKey: .steps)
        policy = try container.decodeIfPresent(BatchExecutionPolicy.self, forKey: .policy) ?? .stopOnError
        guard !steps.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .steps,
                in: container,
                debugDescription: "BatchPlan requires at least one step"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        try container.encode(policy, forKey: .policy)
    }
}
