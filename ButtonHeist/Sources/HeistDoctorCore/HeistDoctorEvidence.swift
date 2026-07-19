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
        guard let dispatchResult = actionEvidence.dispatchResult else {
            throw HeistDoctorError.missingActionResult(path: step.path)
        }
        guard let trace = dispatchResult.accessibilityTrace,
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
                failureKind: actionEvidence.reportedResult?.outcome.failureKind,
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
            method: dispatchResult.method,
            expectation: actionEvidence.checkedExpectation,
            outcome: outcome
        )
    }

    private static func repairMessage(
        step: HeistExecutionStepResult,
        evidence: HeistActionEvidence
    ) -> String? {
        step.failure?.observed
            ?? evidence.reportedResult?.message
            ?? evidence.checkedExpectation?.actual
    }
}
