import TheScore
import ThePlans

extension TheFence {

    static func decodeRotorRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let rotor = try input.value(FenceParameters.rotorName)
        let rotorIndex = try input.nonNegativeValue(FenceParameters.rotorIndex)
        if rotor != nil, rotorIndex != nil {
            throw SchemaValidationError(
                field: "rotor/rotorIndex",
                observed: input.observedDescription,
                expected: "either rotor or rotorIndex"
            )
        }
        let selection: RotorSelection = if let rotor {
            .named(rotor)
        } else if let rotorIndex {
            .index(rotorIndex)
        } else {
            .automatic
        }
        return try appInteractionDispatch(
            Command.rotor,
            .rotor(
                selection: selection,
                target: .target(try input.requiredElementTarget(command: .rotor)),
                direction: try input.value(
                    FenceParameters.rotorDirection,
                    defaultFrom: Command.rotor.descriptor
                )
            ),
            expectationPayload: expectationPayload
        )
    }
}
