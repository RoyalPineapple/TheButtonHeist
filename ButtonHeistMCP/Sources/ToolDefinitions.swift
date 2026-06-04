import ButtonHeist
import MCP

enum ToolDefinitions {
    static var all: [Tool] {
        TheFence.Command.descriptors
            .filter { $0.mcpExposure == .directTool }
            .map(tool(for:))
    }

    private static func tool(for descriptor: FenceCommandDescriptor) -> Tool {
        let descriptorSchema = value(from: descriptor.inputJSONSchema)
        let schema = descriptor.command == .runHeist
            ? runHeistAdapterSchema(from: descriptorSchema)
            : descriptorSchema
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

    private static func runHeistAdapterSchema(from schema: Value) -> Value {
        guard case .object(var object) = schema,
              case .object(var properties)? = object["properties"] else {
            return schema
        }
        properties["source_file"] = .object([
            "type": .string("string"),
            "minLength": .int(1),
        ])
        properties["entry"] = .object([
            "type": .string("string"),
            "minLength": .int(1),
        ])
        object["properties"] = .object(properties)
        object.removeValue(forKey: "required")
        return .object(object)
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
