import TheScore
import ThePlans

extension TheFence {

    static func decodeGetPasteboardRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence in
            try await fence.handleGetPasteboard()
        }
    }

    static func decodeGetAnnouncementsRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence in
            try await fence.handleGetAnnouncements()
        }
    }

    static func decodeDismissKeyboardRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            SemanticActionCommand.dismissKeyboard.command,
            .dismissKeyboard,
            expectationPayload: expectationPayload
        )
    }

    static func decodeTypeTextRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let replacingExisting = try input.value(
            FenceParameters.replacingExisting,
            defaultFrom: Command.typeText.descriptor
        )
        let text = try input.requiredValue(FenceParameters.text)
        if text.isEmpty, !replacingExisting {
            throw SchemaValidationError(field: input.field(.text), observed: "string \"\"", expected: "non-empty string")
        }
        return try appInteractionDispatch(
            SemanticActionCommand.typeText.command,
            .typeText(
                text: .literal(text),
                target: try input.decodedElementTarget().map(ElementTargetExpr.target),
                replacingExisting: replacingExisting
            ),
            expectationPayload: expectationPayload
        )
    }

    static func decodeEditActionRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            SemanticActionCommand.editAction.command,
            .editAction(EditActionTarget(
                action: try input.requiredValue(FenceParameters.editAction)
            )),
            expectationPayload: expectationPayload
        )
    }

    static func decodeSetPasteboardRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let text = try input.nonEmptyValue(FenceParameters.pasteboardText)
        return try appInteractionDispatch(
            SemanticActionCommand.setPasteboard.command,
            .setPasteboard(SetPasteboardTarget(text: text)),
            expectationPayload: expectationPayload
        )
    }
}
