import ThePlans
import TheScore

extension HeistDoctor {
    static func passedRepairEvidence(from step: HeistExecutionStepResult) throws -> HeistPassedStepRepairEvidence {
        guard step.status == .passed else {
            throw HeistDoctorError.stepStatus(path: step.path, expected: .passed, actual: step.status)
        }
        let evidence = try repairEvidenceFields(from: step)
        return HeistPassedStepRepairEvidence(
            stepPath: evidence.stepPath,
            actionIdentity: evidence.actionIdentity,
            target: evidence.target,
            beforeSnapshot: evidence.beforeSnapshot,
            afterDelta: evidence.afterDelta,
            afterSnapshot: evidence.afterSnapshot,
            result: RepairPassEvidence(
                method: evidence.actionResult.method,
                expectation: evidence.expectation
            )
        )
    }

    static func failedRepairEvidence(from step: HeistExecutionStepResult) throws -> HeistFailedStepRepairEvidence {
        guard step.status == .failed else {
            throw HeistDoctorError.stepStatus(path: step.path, expected: .failed, actual: step.status)
        }
        let evidence = try repairEvidenceFields(from: step)
        return HeistFailedStepRepairEvidence(
            stepPath: evidence.stepPath,
            actionIdentity: evidence.actionIdentity,
            target: evidence.target,
            beforeSnapshot: evidence.beforeSnapshot,
            afterDelta: evidence.afterDelta,
            afterSnapshot: evidence.afterSnapshot,
            result: RepairFailureEvidence(
                method: evidence.actionResult.method,
                errorKind: repairErrorKind(evidence.actionEvidence),
                message: repairMessage(step: step, evidence: evidence.actionEvidence),
                expectation: evidence.expectation
            )
        )
    }

    private static func repairEvidenceFields(from step: HeistExecutionStepResult) throws -> RepairEvidenceFields {
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
        guard let command = actionEvidence.command else {
            throw HeistDoctorError.missingActionEvidence(path: step.path)
        }

        return RepairEvidenceFields(
            stepPath: step.path,
            actionIdentity: HeistRepairActionIdentity(command: command),
            target: target,
            beforeSnapshot: before,
            afterDelta: trace.meaningfulEndpointDelta,
            afterSnapshot: trace.captures.last?.interface,
            actionResult: actionResult,
            actionEvidence: actionEvidence,
            expectation: actionEvidence.expectation
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

private struct RepairEvidenceFields {
    let stepPath: String
    let actionIdentity: HeistRepairActionIdentity
    let target: ElementTarget
    let beforeSnapshot: Interface
    let afterDelta: AccessibilityTrace.Delta?
    let afterSnapshot: Interface?
    let actionResult: ActionResult
    let actionEvidence: HeistActionEvidence
    let expectation: ExpectationResult?
}
