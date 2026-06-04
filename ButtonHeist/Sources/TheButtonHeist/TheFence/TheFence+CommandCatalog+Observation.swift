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
                description: """
                    Read the app accessibility hierarchy, optionally scoped to a subtree.

                    containerName is ButtonHeist's generated name for a container in the current interface capture. \
                    It is useful for inspection and viewport/debug commands. It is not a semantic target and is not \
                    recorded into heists.
                    """
            ),
            commandDescriptor(
                .getScreen, requestDecoder: TheFence.decodeGetScreenRequest,
                parameters: [param(.output, .string), param(.inlineData, .boolean), param(.includeInterface, .boolean)],
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Capture a PNG screenshot with optional inline data and interface state."
            ),
            commandDescriptor(
                .wait, requestDecoder: TheFence.decodeWaitRequest,
                isHeistExecutable: true,
                parameters: FenceParameterBlocks.wait,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true),
                description: "Wait until an accessibility predicate is satisfied within timeout "
                    + "by evaluating settled semantic observations."
            ),
        ]
    }
}
