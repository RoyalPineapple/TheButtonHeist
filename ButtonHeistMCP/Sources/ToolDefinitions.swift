@_spi(ButtonHeistTooling) import ButtonHeist
import MCP

enum ToolDefinitions {
    static var all: [Tool] {
        TheFence.Command.descriptors
            .filter { $0.mcpExposure == .directTool }
            .map(tool(for:))
    }

    private static func tool(for descriptor: FenceCommandDescriptor) -> Tool {
        let schema = MCPValueBridge.value(from: descriptor.inputJSONSchema)
        if let annotations = descriptor.mcpAnnotations {
            return Tool(
                name: descriptor.command.rawValue,
                description: descriptor.description,
                inputSchema: schema,
                annotations: .init(
                    readOnlyHint: annotations.readOnlyHint,
                    idempotentHint: annotations.idempotentHint
                )
            )
        }

        return Tool(
            name: descriptor.command.rawValue,
            description: descriptor.description,
            inputSchema: schema
        )
    }
}
