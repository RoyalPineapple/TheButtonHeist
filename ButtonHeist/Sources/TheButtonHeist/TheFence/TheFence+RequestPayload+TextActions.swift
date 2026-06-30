import TheScore
import ThePlans

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
        appInteractionDispatch(SemanticActionCommand.dismissKeyboard.command, .dismissKeyboard)
    }

    static func decodeTypeTextRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let replacingExisting = try input.schemaBoolean("replacingExisting") ?? false
        let text = try input.requiredSchemaString("text")
        if text.isEmpty, !replacingExisting {
            throw SchemaValidationError(field: input.field("text"), observed: "string \"\"", expected: "non-empty string")
        }
        return appInteractionDispatch(
            SemanticActionCommand.typeText.command,
            .typeText(
                text: .literal(text),
                target: try input.decodedElementTarget().map(ElementTargetExpr.target),
                replacingExisting: replacingExisting
            )
        )
    }

    static func decodeEditActionRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(
            SemanticActionCommand.editAction.command,
            .editAction(EditActionTarget(
                action: try input.requiredSchemaEnum("action", as: EditAction.self)
            ))
        )
    }

    static func decodeSetPasteboardRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let text = try input.nonEmptyString("text")
        return appInteractionDispatch(
            SemanticActionCommand.setPasteboard.command,
            .setPasteboard(SetPasteboardTarget(text: text))
        )
    }
}
