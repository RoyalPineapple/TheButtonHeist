import Foundation

package extension HeistPlanAdmissionCandidate {
    func validatedSemantics(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) throws -> HeistPlan {
        var validator = HeistPlanRuntimeSafetyValidator(limits: limits)
        return try validator.validate(self)
    }

    func validatedForRuntimeSafety(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) throws -> HeistPlan {
        try validatedSemantics(limits: limits)
    }
}
