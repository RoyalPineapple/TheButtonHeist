import TheScore

extension TheFence {

    func decodeTextActionDispatch(
        command: Command,
        input: ElementActionRequestInput
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .typeText:
            return try decodedExecutablePayload(.typeText(TypeTextTarget(
                text: input.nonEmptyString("text"),
                elementTarget: input.elementTarget(in: self)
            )))
        case .editAction:
            return try decodedExecutablePayload(.editAction(EditActionTarget(
                action: input.requiredEnumValue("action", as: EditAction.self)
            )))
        case .setPasteboard:
            return try decodedExecutablePayload(.setPasteboard(SetPasteboardTarget(
                text: input.requiredString("text")
            )))
        default:
            throw FenceError.invalidRequest("Unexpected text action command: \(command.rawValue)")
        }
    }
}
