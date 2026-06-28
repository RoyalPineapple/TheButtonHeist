import TheScore
import ThePlans

extension TheFence {

    static func decodeWaitRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let predicate = try ExpectationPayload.parseRequiredPredicate(input.argumentValues["predicate"])
        return decodedExecutablePayload(.wait(WaitTarget(
            predicate: predicate,
            timeout: try input.schemaNumber("timeout")
        )))
    }
}
