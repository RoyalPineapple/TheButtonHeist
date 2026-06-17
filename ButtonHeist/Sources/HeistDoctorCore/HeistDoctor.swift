import Foundation
import TheScore

public enum HeistDoctor {
    public static func suggestions(
        lastPass: HeistExecutionResult,
        newFail: HeistExecutionResult,
        stepPath requestedStepPath: String? = nil
    ) throws -> [HeistRepairSuggestion] {
        let currentStep = try selectedCurrentFailure(in: newFail, stepPath: requestedStepPath)
        let lastStep = try selectedLastSuccess(in: lastPass, matching: currentStep.path)
        let request = HeistRepairRequest(
            lastSuccess: try repairEvidence(from: lastStep, expectedStatus: .passed),
            currentFailure: try repairEvidence(from: currentStep, expectedStatus: .failed)
        )
        let suggestions = HeistRepairSuggester.suggestions(for: request)
        guard !suggestions.isEmpty else {
            throw HeistDoctorError.noSafeSuggestion(
                path: currentStep.path,
                reason: HeistRepairSuggester.noSuggestionReason(for: request)
            )
        }
        return suggestions
    }

    private static func selectedCurrentFailure(
        in receipt: HeistExecutionResult,
        stepPath: String?
    ) throws -> HeistExecutionStepResult {
        if let stepPath {
            let step = try receipt.actionStep(at: stepPath)
            guard step.status == .failed else {
                throw HeistDoctorError.stepStatus(path: stepPath, expected: .failed, actual: step.status)
            }
            return step
        }

        guard let failed = receipt.firstFailedStep else {
            throw HeistDoctorError.noFailedStep
        }
        guard failed.kind == .action else {
            throw HeistDoctorError.nonActionStep(path: failed.path, kind: failed.kind)
        }
        return failed
    }

    private static func selectedLastSuccess(
        in receipt: HeistExecutionResult,
        matching stepPath: String
    ) throws -> HeistExecutionStepResult {
        let step = try receipt.actionStep(at: stepPath)
        guard step.status == .passed else {
            throw HeistDoctorError.stepStatus(path: stepPath, expected: .passed, actual: step.status)
        }
        return step
    }

}

public enum HeistDoctorError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    case noFailedStep
    case stepNotFound(path: String)
    case nonActionStep(path: String, kind: HeistExecutionStepKind)
    case stepStatus(path: String, expected: HeistExecutionStepStatus, actual: HeistExecutionStepStatus)
    case missingActionEvidence(path: String)
    case missingTarget(path: String)
    case missingActionResult(path: String)
    case missingTrace(path: String)
    case noSafeSuggestion(path: String, reason: String)

    public var description: String {
        switch self {
        case .noFailedStep:
            return "new failing receipt does not contain a failed step"
        case .stepNotFound(let path):
            return "no action step found at \(path)"
        case .nonActionStep(let path, let kind):
            return "step at \(path) is \(kind.rawValue); heist-doctor only repairs action steps"
        case .stepStatus(let path, let expected, let actual):
            return "step at \(path) is \(actual.rawValue); expected \(expected.rawValue)"
        case .missingActionEvidence(let path):
            return "action step at \(path) has no action evidence"
        case .missingTarget(let path):
            return "action step at \(path) has no durable target"
        case .missingActionResult(let path):
            return "action step at \(path) has no action result"
        case .missingTrace(let path):
            return "action step at \(path) has no accessibility trace"
        case .noSafeSuggestion(let path, let reason):
            return "unable to make a repair suggestion for action step at \(path): \(reason)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

private extension HeistExecutionResult {
    func actionStep(at path: String) throws -> HeistExecutionStepResult {
        guard let step = steps.flattenedExecutionSteps().first(where: { $0.path == path && $0.kind == .action }) else {
            throw HeistDoctorError.stepNotFound(path: path)
        }
        return step
    }
}

private extension Array where Element == HeistExecutionStepResult {
    func flattenedExecutionSteps() -> [HeistExecutionStepResult] {
        flatMap { [$0] + $0.children.flattenedExecutionSteps() }
    }
}
