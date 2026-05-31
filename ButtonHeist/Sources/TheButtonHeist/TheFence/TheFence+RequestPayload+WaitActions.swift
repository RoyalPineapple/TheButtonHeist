import TheScore

extension TheFence {

    static func decodeWaitForChangeRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        decodedExecutablePayload(.waitForChange(WaitForChangeTarget(
            expect: expectationPayload.expectation,
            timeout: expectationPayload.timeout
        )))
    }

    static func decodeWaitForRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try decodedExecutablePayload(.waitFor(WaitForTarget(
            elementTarget: input.requiredElementTarget(command: .waitFor),
            absent: input.schemaBoolean("absent"),
            timeout: input.schemaNumber("timeout")
        )))
    }
}
