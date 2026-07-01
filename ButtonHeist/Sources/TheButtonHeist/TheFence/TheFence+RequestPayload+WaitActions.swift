import TheScore
import ThePlans

extension TheFence {

    static func decodeWaitRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let predicate = try ExpectationPayload.parseRequiredPredicate(input.value(for: .predicate))
        return waitDispatch(WaitStep(
            predicate: predicate,
            timeout: min(try input.value(FenceParameters.timeout) ?? defaultWaitTimeout, defaultWaitTimeout)
        ))
    }
}
