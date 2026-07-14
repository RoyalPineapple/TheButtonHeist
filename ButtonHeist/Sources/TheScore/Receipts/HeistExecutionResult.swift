import Foundation

// MARK: - Heist Execution Receipt

/// Durable receipt for executing a `HeistPlan`.
public struct HeistExecutionResult: Codable, Sendable, Equatable {
    public let outcome: HeistExecutionOutcome
    public let durationMs: Int

    public var steps: [HeistExecutionStepResult] {
        outcome.steps
    }

    public var abortedAtPath: String? {
        outcome.abortedAtPath
    }

    package static func passed(
        steps: [HeistExecutionStepResult],
        durationMs: Int
    ) -> HeistExecutionResult {
        do {
            try Self.validatePassedSteps(steps, codingPath: [])
            return HeistExecutionResult(
                outcome: .passed(HeistExecutionPassedOutcome(steps: steps)),
                durationMs: durationMs
            )
        } catch {
            preconditionFailure("Invalid passed heist execution result: \(error)")
        }
    }

    package static func failed(
        steps: [HeistExecutionStepResult],
        durationMs: Int,
        abortedAtPath: String
    ) -> HeistExecutionResult {
        do {
            try Self.validateFailedSteps(
                steps,
                abortedAtPath: abortedAtPath,
                codingPath: []
            )
            return HeistExecutionResult(
                outcome: .failed(HeistExecutionFailedOutcome(
                    steps: steps,
                    abortedAtPath: abortedAtPath
                )),
                durationMs: durationMs
            )
        } catch {
            preconditionFailure("Invalid failed heist execution result: \(error)")
        }
    }

    package init(
        steps: [HeistExecutionStepResult],
        durationMs: Int,
        abortedAtPath: String? = nil
    ) {
        self.durationMs = durationMs
        do {
            if let abortedAtPath {
                try Self.validateFailedSteps(
                    steps,
                    abortedAtPath: abortedAtPath,
                    codingPath: []
                )
                outcome = .failed(HeistExecutionFailedOutcome(
                    steps: steps,
                    abortedAtPath: abortedAtPath
                ))
            } else {
                try Self.validatePassedSteps(steps, codingPath: [])
                outcome = .passed(HeistExecutionPassedOutcome(steps: steps))
            }
        } catch {
            preconditionFailure("Invalid heist execution result: \(error)")
        }
    }

    private init(
        outcome: HeistExecutionOutcome,
        durationMs: Int
    ) {
        self.outcome = outcome
        self.durationMs = durationMs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case steps
        case durationMs
        case abortedAtPath
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist execution result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let steps = try container.decode([HeistExecutionStepResult].self, forKey: .steps)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        outcome = try Self.decodeOutcome(
            steps: steps,
            abortedAtPath: try container.decodeIfPresent(String.self, forKey: .abortedAtPath),
            codingPath: container.codingPath
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encodeIfPresent(abortedAtPath, forKey: .abortedAtPath)
    }

    private static func decodeOutcome(
        steps: [HeistExecutionStepResult],
        abortedAtPath: String?,
        codingPath: [CodingKey]
    ) throws -> HeistExecutionOutcome {
        switch abortedAtPath {
        case .none:
            try validatePassedSteps(steps, codingPath: codingPath)
            return .passed(HeistExecutionPassedOutcome(steps: steps))
        case .some(let abortedAtPath):
            try validateFailedSteps(
                steps,
                abortedAtPath: abortedAtPath,
                codingPath: codingPath
            )
            return .failed(HeistExecutionFailedOutcome(steps: steps, abortedAtPath: abortedAtPath))
        }
    }

    private static func validatePassedSteps(
        _ steps: [HeistExecutionStepResult],
        codingPath: [CodingKey]
    ) throws {
        guard let failedPath = firstFailedPath(in: steps) else { return }
        throw receiptError(
            "failed heist execution result must include abortedAtPath for \(failedPath)",
            codingPath: codingPath + [CodingKeys.abortedAtPath]
        )
    }

    private static func validateFailedSteps(
        _ steps: [HeistExecutionStepResult],
        abortedAtPath: String,
        codingPath: [CodingKey]
    ) throws {
        guard let failedPath = firstFailedPath(in: steps) else {
            throw receiptError(
                "passed heist execution result must not include abortedAtPath \(abortedAtPath)",
                codingPath: codingPath + [CodingKeys.abortedAtPath]
            )
        }
        guard abortedAtPath == failedPath else {
            throw receiptError(
                "heist execution abortedAtPath \(abortedAtPath) must match first failed step \(failedPath)",
                codingPath: codingPath + [CodingKeys.abortedAtPath]
            )
        }
    }

    private static func firstFailedPath(in steps: [HeistExecutionStepResult]) -> String? {
        steps.firstFailedStepInReceiptOrder?.path
    }

    private static func receiptError(_ message: String, codingPath: [CodingKey]) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
    }
}

public enum HeistExecutionOutcome: Sendable, Equatable {
    case passed(HeistExecutionPassedOutcome)
    case failed(HeistExecutionFailedOutcome)

    public var steps: [HeistExecutionStepResult] {
        switch self {
        case .passed(let outcome):
            return outcome.steps
        case .failed(let outcome):
            return outcome.steps
        }
    }

    public var abortedAtPath: String? {
        switch self {
        case .passed:
            return nil
        case .failed(let outcome):
            return outcome.abortedAtPath
        }
    }
}

public struct HeistExecutionPassedOutcome: Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]

    fileprivate init(steps: [HeistExecutionStepResult]) {
        self.steps = steps
    }
}

public struct HeistExecutionFailedOutcome: Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]
    public let abortedAtPath: String

    fileprivate init(
        steps: [HeistExecutionStepResult],
        abortedAtPath: String
    ) {
        self.steps = steps
        self.abortedAtPath = abortedAtPath
    }
}
