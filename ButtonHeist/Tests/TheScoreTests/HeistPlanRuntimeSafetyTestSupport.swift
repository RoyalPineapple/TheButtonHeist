import Testing
@_spi(ButtonHeistInternals) import ThePlans
@testable import TheScore

func structurallyAdmittedPlan(
    name: HeistPlanName? = nil,
    parameter: HeistParameter = .none,
    definitions: [HeistPlan] = [],
    body: [HeistStep] = []
) -> HeistPlan {
    do {
        return try HeistPlan(
            structuralVersion: HeistPlan.currentVersion,
            name: name,
            parameter: parameter,
            definitions: definitions,
            body: body
        )
    } catch {
        preconditionFailure("test plan structure must be admitted: \(error)")
    }
}

func runtimeSafetyFailures(
    for plan: HeistPlan,
    limits: HeistPlanRuntimeSafetyLimits = .standard
) -> [HeistPlanRuntimeSafetyFailure] {
    do {
        var validator = HeistPlanRuntimeSafetyValidator(limits: limits)
        _ = try validator.admit(plan)
        return []
    } catch let error as HeistPlanRuntimeSafetyError {
        return error.failures
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
        return []
    }
}
