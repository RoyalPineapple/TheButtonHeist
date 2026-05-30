import ButtonHeist
import MCP

enum ToolDefinitions {
    static var all: [Tool] {
        TheFence.Command.mcpToolContracts.map(tool(for:))
    }

    private static func tool(for contract: MCPToolContract) -> Tool {
        let schema = value(from: contract.inputJSONSchema)
        if let annotations = contract.annotations {
            return Tool(
                name: contract.name,
                description: contract.description,
                inputSchema: schema,
                annotations: .init(
                    readOnlyHint: annotations.readOnlyHint,
                    idempotentHint: annotations.idempotentHint
                )
            )
        }

        return Tool(
            name: contract.name,
            description: contract.description,
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
