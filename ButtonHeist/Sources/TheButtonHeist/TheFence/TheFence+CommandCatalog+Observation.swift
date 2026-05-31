import TheScore

extension TheFence.Command {
    static var observationCommandDescriptors: [FenceCommandDescriptor] {
        [
            commandDescriptor(
                .getInterface, requestDecoder: TheFence.decodeGetInterfaceRequest,
                parameters: FenceParameterBlocks.elementFilter + [
                    FenceParameterBlocks.interfaceSubtree,
                    param(.detail, .string, enumValues: fenceEnumValues(InterfaceDetail.self)),
                ],
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Read the app accessibility hierarchy, optionally scoped to a subtree."
            ),
            commandDescriptor(
                .getScreen, requestDecoder: TheFence.decodeGetScreenRequest,
                parameters: [param(.output, .string), param(.inlineData, .boolean), param(.includeInterface, .boolean)],
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Capture a PNG screenshot with optional inline data and interface state."
            ),
            commandDescriptor(
                .waitForChange, requestDecoder: TheFence.decodeWaitForChangeRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.expectation,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true),
                description: "Wait for any UI change or for an expectation to become true."
            ),
            commandDescriptor(
                .waitFor, requestDecoder: TheFence.decodeWaitForRequest,
                isBatchExecutable: true,
                parameters: FenceParameterBlocks.elementTarget + [
                    param(.absent, .boolean),
                    FenceParameterBlocks.expectationTimeout,
                    FenceParameterBlocks.expect,
                ],
                description: "Wait for a semantic element to appear or disappear."
            ),
        ]
    }
}
