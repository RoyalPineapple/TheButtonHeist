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

    public static func passed(
        steps: [HeistExecutionStepResult],
        durationMs: Int
    ) -> HeistExecutionResult {
        do {
            return HeistExecutionResult(
                outcome: try Self.validatedOutcome(
                    steps: steps,
                    abortedAtPath: nil,
                    codingPath: []
                ),
                durationMs: durationMs
            )
        } catch {
            preconditionFailure("Invalid passed heist execution result: \(error)")
        }
    }

    public static func failed(
        steps: [HeistExecutionStepResult],
        durationMs: Int,
        abortedAtPath: String
    ) -> HeistExecutionResult {
        do {
            return HeistExecutionResult(
                outcome: try Self.validatedOutcome(
                    steps: steps,
                    abortedAtPath: abortedAtPath,
                    codingPath: []
                ),
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
        let failedPath = steps.lazy.compactMap(\.firstFailedStepPathForReceiptValidation).first
        do {
            outcome = try Self.validatedOutcome(
                steps: steps,
                abortedAtPath: abortedAtPath ?? failedPath,
                codingPath: []
            )
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
        outcome = try Self.validatedOutcome(
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

    private static func validatedOutcome(
        steps: [HeistExecutionStepResult],
        abortedAtPath: String?,
        codingPath: [CodingKey]
    ) throws -> HeistExecutionOutcome {
        let failedPath = steps.lazy.compactMap(\.firstFailedStepPathForReceiptValidation).first
        switch (abortedAtPath, failedPath) {
        case (.none, .none):
            return .passed(HeistExecutionPassedOutcome(steps: steps))
        case (.none, .some(let failedPath)):
            throw Self.receiptError(
                "failed heist execution result must include abortedAtPath for \(failedPath)",
                codingPath: codingPath + [CodingKeys.abortedAtPath]
            )
        case (.some(let abortedAtPath), .none):
            throw Self.receiptError(
                "passed heist execution result must not include abortedAtPath \(abortedAtPath)",
                codingPath: codingPath + [CodingKeys.abortedAtPath]
            )
        case (.some(let abortedAtPath), .some(let failedPath)):
            guard abortedAtPath == failedPath else {
                throw Self.receiptError(
                    "heist execution abortedAtPath \(abortedAtPath) must match first failed step \(failedPath)",
                    codingPath: codingPath + [CodingKeys.abortedAtPath]
                )
            }
            return .failed(HeistExecutionFailedOutcome(steps: steps, abortedAtPath: abortedAtPath))
        }
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
