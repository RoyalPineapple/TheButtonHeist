import TheScore

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
        let continuation = try input.rotorContinuation()
        return try Self.decodedExecutablePayload(.rotor(RotorTarget(
            elementTarget: input.requiredElementTarget(command: .rotor),
            selection: selection,
            direction: input.schemaEnum("direction", as: RotorDirection.self) ?? .next,
            continuation: continuation
        )))
    }
}

extension TheFence.CommandArgumentEnvelope {
    func rotorContinuation() throws -> RotorContinuation {
        guard let continuation = try schemaDictionary("continuation") else {
            return .none
        }
        try continuation.rejectUnknownKeys(allowed: ["heistId", "textRange"], expected: "valid rotor continuation field")
        let heistId = try continuation.requiredSchemaString("heistId")
        guard let textRange = try continuation.schemaDictionary("textRange") else {
            return .item(heistId)
        }
        try textRange.rejectUnknownKeys(allowed: ["startOffset", "endOffset"], expected: "valid rotor text range field")
        let startOffset = try textRange.requiredSchemaInteger("startOffset")
        let endOffset = try textRange.requiredSchemaInteger("endOffset")
        guard startOffset >= 0, endOffset >= startOffset else {
            throw SchemaValidationError(
                field: textRange.field("startOffset") + "/" + textRange.field("endOffset"),
                observed: "\(startOffset)..<\(endOffset)",
                expected: "integer range with start >= 0 and end >= start"
            )
        }
        return .textRange(heistId, TextRangeReference(startOffset: startOffset, endOffset: endOffset))
    }
}
