import ButtonHeist
import MCP

enum ToolDefinitions {
    // NOTE: Video data handling
    // Recording responses return artifact paths plus metadata by default.
    // Raw base64 video data and full interaction logs are opt-in and capped
    // before rendering because they can overwhelm the MCP context window.

    static var all: [Tool] {
        TheFence.Command.mcpToolContracts.map(tool(for:))
    }

    static func inputSchema(for contract: MCPToolContract) -> Value {
        value(from: contract.inputJSONSchema)
    }

    static func schemaProperties(from specs: [FenceParameterSpec]) -> [String: Value] {
        FenceParameterSpec.jsonSchemaProperties(from: specs).mapValues { value(from: $0) }
    }

    static func schemaProperty(for spec: FenceParameterSpec) -> Value {
        value(from: spec.jsonSchemaProperty)
    }

    static func schemaType(for type: FenceParameterSpec.ParamType) -> String {
        type.jsonSchemaType
    }

    private static func tool(for contract: MCPToolContract) -> Tool {
        let schema = inputSchema(for: contract)
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

    private static func value(from schemaValue: FenceJSONSchemaValue) -> Value {
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
