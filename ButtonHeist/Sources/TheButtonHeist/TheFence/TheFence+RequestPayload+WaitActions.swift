import TheScore

extension TheFence {

    func decodeWaitActionDispatch(
        command: Command,
        input: ElementActionRequestInput
    ) throws -> DecodedRequestDispatch {
        guard command == .waitFor else {
            throw FenceError.invalidRequest("Unexpected wait action command: \(command.rawValue)")
        }
        return try decodedExecutablePayload(.waitFor(WaitForTarget(
            elementTarget: input.requiredElementTarget(command: .waitFor, in: self),
            absent: input.boolean("absent"),
            timeout: input.number("timeout")
        )))
    }
}
