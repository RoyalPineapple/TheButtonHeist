import TheScore

extension TheFence.Command {
    static var runHeistCommandDescriptor: FenceCommandDescriptor {
        commandDescriptor(
            .runHeist, requestDecoder: TheFence.decodeRunHeistCommandRequest,
            parameters: [
                param(.version, .integer, required: true),
                param(
                    .body, .array, required: true,
                    minItems: 1,
                    maxItems: TheFence.DecodeLimits.maxRunHeistSteps,
                    arrayItemType: .object,
                    arrayItemProperties: [
                        param(
                            .type,
                            .string,
                            required: true,
                            enumValues: [
                                "action",
                                "wait",
                                "conditional",
                                "wait_for_cases",
                                "for_each_element",
                                "for_each_string",
                                "heist",
                                "invoke",
                                "warn",
                                "fail",
                            ]
                        ),
                    ],
                    arrayItemAdditionalProperties: true
                )
            ],
            description: "Execute an inline typed heist plan."
        )
    }
}
