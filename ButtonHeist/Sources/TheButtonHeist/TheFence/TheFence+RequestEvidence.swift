import TheScore

extension TheFence.ParsedRequest {
    @ButtonHeistActor
    func heistRecordingElementTarget() throws -> ElementTarget? {
        try arguments.elementTarget()
    }

    @ButtonHeistActor
    func heistRecordingCoordinateOnly() throws -> Bool {
        guard try arguments.elementTarget() == nil else { return false }
        return command.requestPayloadKind == .gesture
    }

    func heistRecordingArguments() -> [String: HeistValue] {
        var values = arguments.argumentValues
        values.removeValue(forKey: "requestId")
        values.removeValue(forKey: "target")
        values.removeValue(forKey: "expect")

        if !command.recordsTimeoutAsHeistArgument {
            values.removeValue(forKey: "timeout")
        }

        return values
    }
}

private extension TheFence.Command {
    var recordsTimeoutAsHeistArgument: Bool {
        descriptor.actionResultMethod == .waitFor || descriptor.actionResultMethod == .waitForChange
    }
}
