import ThePlans
import TheScore

extension HeistDoctor {
    static func repairEvidence(from step: HeistExecutionStepResult) throws -> HeistRepairEvidence {
        guard let actionEvidence = step.actionEvidence else {
            throw HeistDoctorError.missingActionEvidence(path: step.path)
        }
        guard let command = step.actionCommand else {
            throw HeistDoctorError.missingActionEvidence(path: step.path)
        }
        guard let target = step.reportTarget else {
            throw HeistDoctorError.missingTarget(path: step.path)
        }
        guard let result = actionEvidence.result else {
            throw HeistDoctorError.missingActionResult(path: step.path)
        }
        guard let trace = result.accessibilityTrace,
              let before = trace.captures.first?.interface
        else {
            throw HeistDoctorError.missingTrace(path: step.path)
        }

        let outcome: HeistRepairEvidenceOutcome
        switch step.status {
        case .passed:
            outcome = .passed
        case .failed:
            outcome = .failed(
                failureKind: result.outcome.failureKind,
                message: repairMessage(step: step, evidence: actionEvidence)
            )
        case .skipped:
            throw HeistDoctorError.stepStatus(path: step.path, expected: .passed, actual: .skipped)
        }

        return HeistRepairEvidence(
            stepPath: step.path,
            command: command,
            target: target,
            beforeSnapshot: before,
            changeFacts: trace.changeFacts,
            method: result.method,
            expectation: actionEvidence.expectation,
            outcome: outcome
        )
    }

    private static func repairMessage(
        step: HeistExecutionStepResult,
        evidence: HeistActionEvidence
    ) -> String? {
        step.failure?.observed
            ?? evidence.result?.message
            ?? evidence.expectation?.actual
    }
}
