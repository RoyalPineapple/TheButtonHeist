import TheScore

extension HeistDoctor {
    static func repairEvidence(
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
