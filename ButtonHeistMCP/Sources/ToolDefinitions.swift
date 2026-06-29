@_spi(ButtonHeistTooling) import ButtonHeist
import MCP

enum ToolDefinitions {
    static var all: [Tool] {
        TheFence.Command.descriptors
            .filter { $0.projection.mcpExposure == .directTool }
            .map(tool(for:))
    }

    private static func tool(for descriptor: FenceCommandDescriptor) -> Tool {
        let schema = value(from: descriptor.inputJSONSchema)
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

    private static func value(from schemaValue: HeistValue) -> Value {
        switch schemaValue {
        case .string(let value):
            return .string(value)
        case .int(let value):
            return .int(value)
        case .double(let value):
            return .double(value)
        case .bool(let value):
            return .bool(value)
        case .array(let values):
            return .array(values.map { value(from: $0) })
        case .object(let values):
            return .object(values.mapValues { value(from: $0) })
        }
    }
}
