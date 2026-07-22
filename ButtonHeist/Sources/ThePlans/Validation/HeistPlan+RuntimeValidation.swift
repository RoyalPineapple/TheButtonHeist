import Foundation

package extension HeistPlanAdmissionCandidate {
    func validatedSemantics(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) throws -> HeistPlan {
        var validator = HeistPlanRuntimeSafetyValidator(limits: limits)
        return try validator.validate(self)
    }

    func semanticValidationResult(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) -> ValidationResult<HeistPlan, HeistBuildDiagnostic> {
        do {
            return .success(try validatedSemantics(limits: limits), diagnostics: [])
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

    func validatedForRuntimeSafety(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) throws -> HeistPlan {
        try validatedSemantics(limits: limits)
    }
}
