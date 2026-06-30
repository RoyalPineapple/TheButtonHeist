@_spi(ButtonHeistTooling) import ButtonHeist
import MCP

enum ToolDefinitions {
    static var all: [Tool] {
        TheFence.Command.descriptors
            .filter { $0.projection.mcpExposure == .directTool }
            .map(tool(for:))
    }

    private static func tool(for descriptor: FenceCommandDescriptor) -> Tool {
        let schema = MCPValueBridge.value(from: descriptor.inputJSONSchema)
        let projection = descriptor.projection
        if let annotations = projection.mcpAnnotations {
            return Tool(
                name: descriptor.command.rawValue,
                description: projection.description,
                inputSchema: schema,
                annotations: .init(
                    readOnlyHint: annotations.readOnlyHint,
                    idempotentHint: annotations.idempotentHint
                )
            )
        }

        return Tool(
            name: descriptor.command.rawValue,
            description: projection.description,
            inputSchema: schema
        )
    }
}
