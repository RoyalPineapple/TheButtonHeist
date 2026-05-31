import TheScore

extension TheFence {

    static func decodeTypeTextRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try decodedExecutablePayload(.typeText(TypeTextTarget(
            text: input.nonEmptyString("text"),
            elementTarget: input.decodedElementTarget()
        )))
    }

    static func decodeEditActionRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try decodedExecutablePayload(.editAction(EditActionTarget(
            action: input.requiredSchemaEnum("action", as: EditAction.self)
        )))
    }

    static func decodeSetPasteboardRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try decodedExecutablePayload(.setPasteboard(SetPasteboardTarget(
            text: input.requiredSchemaString("text")
        )))
    }
}
