enum HeistRuntimeCommand: String, CaseIterable, FenceCommand {
    case runHeist = "run_heist"

    var descriptor: FenceCommandDescriptor {
        TheFence.Command.commandDescriptor(
            command, family: .heistRuntime,
            requestDecoder: TheFence.decodeRunHeistCommandRequest,
            parameters: [
                param(.input, .string),
                param(.version, .integer),
                param(
                    .body, .array,
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
            description: "Execute a typed heist plan, supplied inline (version + body) or loaded by " +
                "the fence from an `input` .heist package artifact path."
        )
    }
}
