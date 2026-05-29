import TheScore

extension TheFence {

    func decodeElementActionDispatch(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge:
            return try decodeScrollActionDispatch(command: command, input: arguments)
        case .activate:
            return try decodeAccessibilityActionDispatch(command: command, input: arguments)
        case .rotor:
            return try decodeRotorActionDispatch(command: command, input: arguments)
        case .typeText, .editAction, .setPasteboard:
            return try decodeTextActionDispatch(command: command, input: arguments)
        case .waitFor:
            return try decodeWaitActionDispatch(command: command, input: arguments)
        default:
            throw FenceError.invalidRequest("Unexpected element action command: \(command.rawValue)")
        }
    }

    func decodedExecutablePayload(_ message: ClientMessage) -> DecodedRequestDispatch {
        Self.clientActionDispatch([message])
    }

}
