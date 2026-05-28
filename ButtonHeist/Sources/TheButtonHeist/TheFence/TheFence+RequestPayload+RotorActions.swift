import TheScore

extension TheFence {

    func decodeRotorActionDispatch(
        command: Command,
        input: ElementActionRequestInput
    ) throws -> DecodedRequestDispatch {
        guard command == .rotor else {
            throw FenceError.invalidRequest("Unexpected rotor action command: \(command.rawValue)")
        }
        let rotor = try input.string("rotor")
        let rotorIndex = try input.nonNegativeInteger("rotorIndex")
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
        return try decodedExecutablePayload(.rotor(RotorTarget(
            elementTarget: input.requiredElementTarget(command: .rotor, in: self),
            selection: selection,
            direction: input.enumValue("direction", as: RotorDirection.self) ?? .next,
            continuation: continuation
        )))
    }
}

extension TheFence.ElementActionRequestInput {
    func rotorContinuation() throws -> RotorContinuation {
        let startOffset = try integer("currentTextStartOffset")
        let endOffset = try integer("currentTextEndOffset")
        if (startOffset == nil) != (endOffset == nil) {
            throw FenceError.invalidRequest("currentTextStartOffset and currentTextEndOffset must be provided together")
        }
        guard let startOffset, let endOffset else {
            guard let currentHeistId = try string("currentHeistId") else {
                return .none
            }
            return .item(currentHeistId)
        }
        guard let currentHeistId = try string("currentHeistId") else {
            throw SchemaValidationError(field: "currentHeistId", observed: "missing", expected: "string")
        }
        guard startOffset >= 0, endOffset >= startOffset else {
            throw SchemaValidationError(
                field: "currentTextStartOffset/currentTextEndOffset",
                observed: "\(startOffset)..<\(endOffset)",
                expected: "integer range with start >= 0 and end >= start"
            )
        }
        return .textRange(currentHeistId, TextRangeReference(startOffset: startOffset, endOffset: endOffset))
    }
}
