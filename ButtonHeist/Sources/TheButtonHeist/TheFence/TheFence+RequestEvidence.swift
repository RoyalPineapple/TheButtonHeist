import TheScore

struct HeistRecordingProjection: Sendable, Equatable {
    let elementTarget: ElementTarget?
    let arguments: [String: HeistValue]
}

extension TheFence.ParsedRequest {
    @ButtonHeistActor
    func heistRecordingProjection() throws -> HeistRecordingProjection {
        let elementTarget = try arguments.decodedElementTarget()
        var values = arguments.argumentValues
        values.removeValue(forKey: "requestId")
        values.removeValue(forKey: "target")
        values.removeValue(forKey: "expect")

        if !command.recordsTimeoutAsHeistArgument {
            values.removeValue(forKey: "timeout")
        }

        if expectationPayload.expectation != nil {
            values["expect"] = arguments.argumentValues["expect"]
            if let timeout = arguments.argumentValues["timeout"] {
                values["timeout"] = timeout
            }
        }

        return HeistRecordingProjection(
            elementTarget: elementTarget,
            arguments: values
        )
    }
}

private extension TheFence.Command {
    var recordsTimeoutAsHeistArgument: Bool {
        self == .waitFor || self == .waitForChange
    }
}
