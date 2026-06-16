@_spi(ButtonHeistInternals) import TheScore

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
        return try appInteractionDispatch(
            SemanticActionCommand.rotor,
            [.rotor(RotorTarget(
                elementTarget: input.requiredElementTarget(command: .rotor),
                selection: selection,
                direction: input.schemaEnum("direction", as: RotorDirection.self)
                    ?? Command.rotor.descriptor.requiredDefaultEnumValue(for: .direction, as: RotorDirection.self)
            ))]
        )
    }
}
