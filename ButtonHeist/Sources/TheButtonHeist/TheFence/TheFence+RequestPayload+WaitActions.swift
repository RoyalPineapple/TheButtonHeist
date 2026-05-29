import TheScore

extension TheFence {

    func decodeWaitActionDispatch(
        command: Command,
        input: some CommandArgumentReadable
    ) throws -> DecodedRequestDispatch {
        guard command == .waitFor else {
            throw FenceError.invalidRequest("Unexpected wait action command: \(command.rawValue)")
        }
        return try decodedExecutablePayload(.waitFor(WaitForTarget(
            elementTarget: input.requiredElementTarget(command: .waitFor),
            absent: input.schemaBoolean("absent"),
            timeout: input.schemaNumber("timeout")
        )))
    }
}
