enum HeistRuntimeCommand: String, CaseIterable, FenceCommand {
    case runHeist = "run_heist"

    var descriptor: FenceCommandDescriptor {
        TheFence.Command.commandDescriptor(
            command, family: .heistRuntime,
            requestDecoder: TheFence.decodeRunHeistCommandRequest,
            parameters: [
                param(.path, .string),
                param(.version, .integer),
                param(.name, .string),
                param(.parameter, .object),
                param(
                    .definitions, .array,
                    arrayItemType: .object,
                    arrayItemAdditionalProperties: true
                ),
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
            description: "Execute a typed heist plan, supplied inline (canonical HeistPlan fields: " +
                "version, name, parameter, definitions, body) or loaded by the fence from a `path` " +
                "to a .heist package artifact. Provide exactly one source: a path or an inline plan."
        )
    }
}
