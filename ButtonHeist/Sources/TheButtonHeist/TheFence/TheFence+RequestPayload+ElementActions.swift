import TheScore

extension TheFence {

    func decodeElementActionDispatch(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws -> DecodedRequestDispatch {
        let input = ElementActionRequestInput(arguments)
        switch command {
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge:
            return try decodeScrollActionDispatch(command: command, input: input)
        case .activate:
            return try decodeAccessibilityActionDispatch(command: command, input: input)
        case .rotor:
            return try decodeRotorActionDispatch(command: command, input: input)
        case .typeText, .editAction, .setPasteboard:
            return try decodeTextActionDispatch(command: command, input: input)
        case .waitFor:
            return try decodeWaitActionDispatch(command: command, input: input)
        default:
            throw FenceError.invalidRequest("Unexpected element action command: \(command.rawValue)")
        }
    }

    func decodedExecutablePayload(_ message: ClientMessage) -> DecodedRequestDispatch {
        Self.clientActionDispatch([message])
    }

    func decodedElementTarget(_ arguments: some CommandArgumentReadable) throws -> ElementTarget? {
        try ElementActionRequestInput(arguments).elementTarget(in: self)
    }

    func decodedElementMatcher(_ arguments: some CommandArgumentReadable) throws -> ElementMatcher {
        try ElementActionRequestInput(arguments).matcher()
    }
}
