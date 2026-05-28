import TheScore

extension TheFence.ParsedRequest {
    @ButtonHeistActor
    func heistRecordingElementTarget() throws -> ElementTarget? {
        try arguments.elementTarget()
    }

    @ButtonHeistActor
    func heistRecordingCoordinateOnly() throws -> Bool {
        guard try arguments.elementTarget() == nil else { return false }
        switch command {
        case .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate, .twoFingerTap,
             .drawPath, .drawBezier:
            return true
        default:
            return false
        }
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
        switch self {
        case .waitFor, .waitForChange:
            return true
        default:
            return false
        }
    }
}
