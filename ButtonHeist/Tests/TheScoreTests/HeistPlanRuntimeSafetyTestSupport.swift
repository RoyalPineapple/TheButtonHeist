import Testing
@_spi(ButtonHeistInternals) import ThePlans
@testable import TheScore

func runtimeSafetyFailures(
    for raw: HeistPlanAdmissionCandidate,
    limits: HeistPlanRuntimeSafetyLimits = .standard
) -> [HeistPlanRuntimeSafetyFailure] {
    do {
        _ = try raw.validatedForRuntimeSafety(limits: limits)
        return []
    } catch let error as HeistPlanRuntimeSafetyError {
        return error.failures
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
        return []
    }
}
