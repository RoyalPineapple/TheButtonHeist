import TheScore

extension TheFence.Command {
    static var runBatchCommandDescriptor: FenceCommandDescriptor {
        commandDescriptor(
            .runBatch, requestDecoder: TheFence.decodeRunBatchCommandRequest,
            parameters: [
                param(
                    .steps, .array, required: true,
                    minItems: 1,
                    maxItems: TheFence.DecodeLimits.maxRunBatchSteps,
                    arrayItemType: .object,
                    arrayItemProperties: [
                        param(
                            .command, .string, required: true,
                            enumValues: Self.batchExecutableCommandDescriptors.map { $0.command.rawValue }
                        ),
                        FenceParameterBlocks.expect,
                    ],
                    arrayItemAdditionalProperties: true
                ),
                param(.policy, .string, enumValues: fenceEnumValues(BatchExecutionPolicy.self)),
            ],
            description: "Execute ordered command steps with batch policy and per-step expectations."
        )
    }
}
