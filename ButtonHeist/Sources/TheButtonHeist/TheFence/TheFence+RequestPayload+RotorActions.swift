import TheScore
import ThePlans

extension TheFence {

    static func decodeRotorRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let rotor = try input.schemaString("rotor")
        let rotorIndex = try input.schemaNonNegativeInteger("rotorIndex")
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
        return appInteractionDispatch(
            SemanticActionCommand.rotor.command,
            .rotor(
                selection: selection,
                target: .target(try input.requiredElementTarget(command: .rotor)),
                direction: try input.schemaEnum("direction", as: RotorDirection.self)
                    ?? Command.rotor.descriptor.requiredDefaultEnumValue(for: .direction, as: RotorDirection.self)
            )
        )
    }
}
