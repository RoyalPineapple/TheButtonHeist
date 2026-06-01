import TheScore

struct HeistStepProjection: Sendable, Equatable {
    let elementTarget: ElementTarget?
    let arguments: [String: HeistValue]
    let expectation: AccessibilityPredicate?

    func heistStep(command: TheFence.Command) throws -> HeistStep {
        try HeistStep(
            command: command.rawValue,
            target: elementTarget,
            arguments: arguments,
            expectation: expectation
        )
    }
}

extension TheFence.ParsedRequest {
    @ButtonHeistActor
    func heistStepProjection() throws -> HeistStepProjection {
        let elementTarget = try arguments.decodedElementTarget()
        return HeistStepProjection(
            elementTarget: elementTarget,
            arguments: command.heistRecordingArguments(
                from: arguments,
                recordsExpectationTimeout: expectationPayload.expectation != nil
            ),
            expectation: expectationPayload.expectation
        )
    }
}

private extension TheFence.Command {
    func heistRecordingArguments(
        from arguments: TheFence.CommandArgumentEnvelope,
        recordsExpectationTimeout: Bool
    ) -> [String: HeistValue] {
        let keys = heistRecordingArgumentKeys(recordsExpectationTimeout: recordsExpectationTimeout)
        return arguments.argumentValues.filter { key, _ in keys.contains(key) }
    }

    func heistRecordingArgumentKeys(recordsExpectationTimeout: Bool) -> Set<String> {
        var keys = Set(descriptor.parameters.map(\.key))
        keys.subtract([
            "requestId",
            FenceParameterKey.target.rawValue,
            FenceParameterKey.expect.rawValue,
        ])

        if !recordsTimeoutAsHeistArgument && !recordsExpectationTimeout {
            keys.remove(FenceParameterKey.timeout.rawValue)
        }
        return keys
    }

    var recordsTimeoutAsHeistArgument: Bool {
        self == .wait
    }
}
