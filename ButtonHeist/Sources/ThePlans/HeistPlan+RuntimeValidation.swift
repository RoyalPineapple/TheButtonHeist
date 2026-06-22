import Foundation

public extension HeistPlanAdmissionCandidate {
    func validatedForRuntimeSafety(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) throws -> HeistPlan {
        var validator = HeistPlanRuntimeSafetyValidator(limits: limits)
        return try validator.validate(self)
    }
}
