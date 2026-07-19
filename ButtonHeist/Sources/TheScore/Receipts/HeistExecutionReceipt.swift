import Foundation

/// Durable receipt for executing a heist plan.
public struct HeistExecutionReceipt: Codable, Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]
    public let durationMs: Int

    public var outcome: HeistExecutionOutcome {
        if let failed = steps.firstFailedStepInReceiptOrder {
            return .failed(abortedAtPath: failed.path)
        }
        return .passed
    }

    public var abortedAtPath: HeistExecutionPath? {
        guard case .failed(let abortedAtPath) = outcome else { return nil }
        return abortedAtPath
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
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution receipt")
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
    case passed
    case failed(abortedAtPath: HeistExecutionPath)
}
