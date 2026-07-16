import Foundation

/// Durable receipt for executing a heist plan.
public struct HeistExecutionResult: Codable, Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]
    public let durationMs: Int

    public var outcome: HeistExecutionOutcome {
        if let failed = steps.firstFailedStepInReceiptOrder {
            return .failed(.init(steps: steps, abortedAtPath: failed.path))
        }
        return .passed(.init(steps: steps))
    }

    public var abortedAtPath: HeistExecutionPath? {
        guard case .failed(let outcome) = outcome else { return nil }
        return outcome.abortedAtPath
    }

    package init(steps: [HeistExecutionStepResult], durationMs: Int) {
        self.steps = steps
        self.durationMs = durationMs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case steps
        case durationMs
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decode([HeistExecutionStepResult].self, forKey: .steps)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        try container.encode(durationMs, forKey: .durationMs)
    }
}

public enum HeistExecutionOutcome: Sendable, Equatable {
    case passed(HeistExecutionPassedOutcome)
    case failed(HeistExecutionFailedOutcome)
}

public struct HeistExecutionPassedOutcome: Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]

    fileprivate init(steps: [HeistExecutionStepResult]) { self.steps = steps }
}

public struct HeistExecutionFailedOutcome: Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]
    public let abortedAtPath: HeistExecutionPath

    fileprivate init(steps: [HeistExecutionStepResult], abortedAtPath: HeistExecutionPath) {
        self.steps = steps
        self.abortedAtPath = abortedAtPath
    }
}
