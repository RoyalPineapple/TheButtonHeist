import TheScore

struct HeistStepProjection: Sendable, Equatable {
    let elementTarget: ElementTarget?
    let arguments: [String: HeistValue]
    let expectation: ActionExpectation?
}

extension TheFence.ParsedRequest {
    @ButtonHeistActor
    func heistStepProjection() throws -> HeistStepProjection {
        let elementTarget = try arguments.decodedElementTarget()
        var values = arguments.argumentValues
        values.removeValue(forKey: "requestId")
        values.removeValue(forKey: "target")
        values.removeValue(forKey: "expect")

        if !command.recordsTimeoutAsHeistArgument {
            values.removeValue(forKey: "timeout")
        }

        if expectationPayload.expectation != nil {
            if let timeout = arguments.argumentValues["timeout"] {
                values["timeout"] = timeout
            }
        }

        return HeistStepProjection(
            elementTarget: elementTarget,
            arguments: values,
            expectation: expectationPayload.expectation
        )
    }
}

private extension TheFence.Command {
    var recordsTimeoutAsHeistArgument: Bool {
        self == .waitFor || self == .waitForChange
    }
}
