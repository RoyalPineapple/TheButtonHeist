@_spi(ButtonHeistInternals) import TheScore

extension TheFence {

    static func decodeGetPasteboardRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence, _ in
            try await fence.handleGetPasteboard()
        }
    }

    static func decodeDismissKeyboardRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(SemanticActionCommand.dismissKeyboard, [.resignFirstResponder])
    }

    static func decodeTypeTextRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            SemanticActionCommand.typeText,
            [.typeText(TypeTextTarget(
                text: input.nonEmptyString("text"),
                elementTarget: input.decodedElementTarget()
            ))]
        )
    }

    static func decodeEditActionRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            SemanticActionCommand.editAction,
            [.editAction(EditActionTarget(
                action: input.requiredSchemaEnum("action", as: EditAction.self)
            ))]
        )
    }

    static func decodeSetPasteboardRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            SemanticActionCommand.setPasteboard,
            [.setPasteboard(SetPasteboardTarget(
                text: input.requiredSchemaString("text")
            ))]
        )
    }
}
