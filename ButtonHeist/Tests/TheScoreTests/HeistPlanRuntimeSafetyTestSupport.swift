import Testing
@_spi(ButtonHeistInternals) import ThePlans
@testable import TheScore

func runtimeSafetyFailures(
    for plan: HeistPlan,
    limits: HeistPlanRuntimeSafetyLimits = .standard
) -> [HeistPlanRuntimeSafetyFailure] {
    do {
        var validator = HeistPlanRuntimeSafetyValidator(limits: limits)
        try validator.validate(plan)
        return []
    } catch let error as HeistPlanRuntimeSafetyError {
        return error.failures
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
        return []
    }
}
