import Foundation

package struct HeistPlanSemanticValidator: Sendable {
    package let limits: HeistPlanRuntimeSafetyLimits

    package init(limits: HeistPlanRuntimeSafetyLimits = .standard) {
        self.limits = limits
    }

    package func validate(_ raw: HeistPlanAdmissionCandidate) throws -> HeistPlan {
        var validator = HeistPlanRuntimeSafetyValidator(limits: limits)
        return try validator.validate(raw)
    }

    package func validationResult(
        _ raw: HeistPlanAdmissionCandidate
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        do {
            return .success(try validate(raw), diagnostics: [])
        } catch let error as HeistPlanRuntimeSafetyError {
            return .failure(error.diagnostics)
        } catch {
            return .failure([HeistBuildDiagnostic(
                code: .planRuntimeSafety,
                phase: .planValidation,
                message: "ButtonHeist plan failed semantic validation: \(String(describing: error))"
            )])
        }
    }
}

package extension HeistPlanAdmissionCandidate {
    func validatedSemantics(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) throws -> HeistPlan {
        try HeistPlanSemanticValidator(limits: limits).validate(self)
    }

    func semanticValidationResult(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        HeistPlanSemanticValidator(limits: limits).validationResult(self)
    }

    func validatedForRuntimeSafety(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) throws -> HeistPlan {
        try validatedSemantics(limits: limits)
    }
}
