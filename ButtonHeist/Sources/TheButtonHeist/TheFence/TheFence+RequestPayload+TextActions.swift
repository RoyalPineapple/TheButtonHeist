import TheScore

extension TheFence {

    func decodeTextActionDispatch(
        command: Command,
        input: CommandArgumentEnvelope
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .typeText:
            return try decodedExecutablePayload(.typeText(TypeTextTarget(
                text: input.nonEmptyString("text"),
                elementTarget: input.decodedElementTarget()
            )))
        case .editAction:
            return try decodedExecutablePayload(.editAction(EditActionTarget(
                action: input.requiredSchemaEnum("action", as: EditAction.self)
            )))
        case .setPasteboard:
            return try decodedExecutablePayload(.setPasteboard(SetPasteboardTarget(
                text: input.requiredSchemaString("text")
            )))
        default:
            throw FenceError.invalidRequest("Unexpected text action command: \(command.rawValue)")
        }
    }
}
