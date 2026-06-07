import Foundation
import ThePlans
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
        return HeistRepairSuggester.suggestions(for: request)
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

    private static func repairEvidence(
        from step: HeistExecutionStepResult,
        expectedStatus: HeistExecutionStepStatus
    ) throws -> HeistStepRepairEvidence {
        guard let actionEvidence = step.actionEvidence else {
            throw HeistDoctorError.missingActionEvidence(path: step.path)
        }
        guard let target = step.reportTarget else {
            throw HeistDoctorError.missingTarget(path: step.path)
        }
        guard let actionResult = actionEvidence.actionResult else {
            throw HeistDoctorError.missingActionResult(path: step.path)
        }
        guard let trace = actionResult.accessibilityTrace,
              let before = trace.captures.first?.interface
        else {
            throw HeistDoctorError.missingTrace(path: step.path)
        }

        let result = HeistStepRepairResult(
            succeeded: step.status == .passed,
            method: actionResult.method,
            errorKind: repairErrorKind(actionEvidence),
            message: repairMessage(step: step, evidence: actionEvidence),
            expectation: actionEvidence.expectation
        )
        guard step.status == expectedStatus else {
            throw HeistDoctorError.stepStatus(path: step.path, expected: expectedStatus, actual: step.status)
        }

        return HeistStepRepairEvidence(
            stepPath: step.path,
            actionKind: step.reportCommandName ?? actionResult.method.rawValue,
            target: target,
            beforeSnapshot: before,
            afterDelta: trace.meaningfulEndpointDelta,
            afterSnapshot: trace.captures.last?.interface,
            result: result
        )
    }

    private static func repairErrorKind(_ evidence: HeistActionEvidence) -> ErrorKind? {
        evidence.actionResult?.errorKind ?? evidence.expectationActionResult?.errorKind
    }

    private static func repairMessage(
        step: HeistExecutionStepResult,
        evidence: HeistActionEvidence
    ) -> String? {
        step.failure?.observed
            ?? evidence.actionResult?.message
            ?? evidence.expectationActionResult?.message
            ?? evidence.expectation?.actual
    }
}

public enum HeistDoctorError: Error, Sendable, Equatable, CustomStringConvertible {
    case noFailedStep
    case stepNotFound(path: String)
    case nonActionStep(path: String, kind: HeistExecutionStepKind)
    case stepStatus(path: String, expected: HeistExecutionStepStatus, actual: HeistExecutionStepStatus)
    case missingActionEvidence(path: String)
    case missingTarget(path: String)
    case missingActionResult(path: String)
    case missingTrace(path: String)

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
        }
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
