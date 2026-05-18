import ButtonHeist
import MCP

enum ToolDefinitions {
    // NOTE: Video data handling
    // The MCP server intentionally omits raw base64 video data from responses.
    // Video payloads can be tens of megabytes which would overwhelm the MCP
    // context window. Instead, video metadata (dimensions, duration, frame count,
    // stop reason, interaction count) is returned as a JSON summary.
    //
    // Agents that need the actual video file should pass the "output" parameter
    // in stop_recording to write to disk and receive only the file path.

    static var all: [Tool] {
        TheFence.Command.mcpToolContracts.map(tool(for:))
    }

    static func inputSchema(for contract: MCPToolContract) -> Value {
        inputSchema(
            properties: schemaProperties(from: contract.parameters),
            required: contract.requiredParameterKeys
        )
    }

    static func schemaProperties(from specs: [FenceParameterSpec]) -> [String: Value] {
        var properties: [String: Value] = [:]
        for spec in specs where properties[spec.key] == nil {
            properties[spec.key] = schemaProperty(for: spec)
        }
        return properties
    }

    static func inputSchema(properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
            "additionalProperties": false,
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    static func schemaProperty(for spec: FenceParameterSpec) -> Value {
        var schema: [String: Value] = ["type": .string(schemaType(for: spec.type))]
        if let description = spec.description { schema["description"] = .string(description) }
        if let enumValues = spec.enumValues { schema["enum"] = .array(enumValues.map { .string($0) }) }
        if let minimum = spec.minimum { schema["minimum"] = schemaNumberValue(minimum) }
        if let maximum = spec.maximum { schema["maximum"] = schemaNumberValue(maximum) }
        if let minLength = spec.minLength { schema["minLength"] = .int(minLength) }

        switch spec.type {
        case .stringArray:
            schema["type"] = "array"
            schema["items"] = ["type": "string"]

        case .object where !spec.objectProperties.isEmpty:
            schema["properties"] = .object(schemaProperties(from: spec.objectProperties))
            let required = spec.objectProperties.filter(\.required).map(\.key)
            if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
            schema["additionalProperties"] = .bool(spec.objectAdditionalProperties)

        case .array:
            if let itemType = spec.arrayItemType {
                var items: [String: Value] = ["type": .string(schemaType(for: itemType))]
                if itemType == .object {
                    items["properties"] = .object(schemaProperties(from: spec.arrayItemProperties))
                    let required = spec.arrayItemProperties.filter(\.required).map(\.key)
                    if !required.isEmpty { items["required"] = .array(required.map { .string($0) }) }
                    items["additionalProperties"] = .bool(spec.arrayItemAdditionalProperties)
                }
                schema["items"] = .object(items)
            }

        default:
            break
        }

        return .object(schema)
    }

    static func schemaType(for type: FenceParameterSpec.ParamType) -> String {
        switch type {
        case .string:
            return "string"
        case .integer:
            return "integer"
        case .number:
            return "number"
        case .boolean:
            return "boolean"
        case .stringArray, .array:
            return "array"
        case .object:
            return "object"
        }
    }

    static func schemaNumberValue(_ value: Double) -> Value {
        if value.rounded(.towardZero) == value {
            return .int(Int(value))
        }
        return .double(value)
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
}
