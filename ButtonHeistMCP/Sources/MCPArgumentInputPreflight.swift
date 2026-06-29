import Foundation
import MCP
@_spi(ButtonHeistTooling) import ButtonHeist

typealias MCPRawArgumentObject = [String: Value]

struct MCPToolRequest {
    let name: String
    let arguments: TheFence.CommandArgumentEnvelope

    init(name: String, arguments: MCPRawArgumentObject?) throws {
        self.name = name
        self.arguments = try MCPArgumentInputPreflight.commandEnvelope(arguments)
    }
}

struct MCPToolArguments {
    let commandEnvelope: TheFence.CommandArgumentEnvelope

    init(_ arguments: MCPRawArgumentObject?) throws {
        commandEnvelope = try MCPArgumentInputPreflight.commandEnvelope(arguments)
    }
}

private enum MCPArgumentInputPreflight {
    static func commandEnvelope(_ arguments: MCPRawArgumentObject?) throws -> TheFence.CommandArgumentEnvelope {
        try validate(arguments)
        return TheFence.CommandArgumentEnvelope(
            values: try heistValues(from: arguments ?? [:])
        )
    }

    private static func heistValues(from arguments: MCPRawArgumentObject) throws -> [String: HeistValue] {
        try arguments.mapValues(heistValue)
    }

    private static func validate(
        _ arguments: MCPRawArgumentObject?,
        context: String = "MCP arguments",
        maxBytes: Int = PublicJSONInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicJSONInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicJSONInputLimits.maxTotalObjectKeys
    ) throws {
        try PublicJSONValuePreflight.validateObject(
            arguments ?? [:],
            policy: PublicJSONInputPolicy(
                maxBytes: maxBytes,
                maxNestingDepth: maxNestingDepth,
                maxTotalObjectKeys: maxTotalObjectKeys,
                nullHandling: .rejected(expected: "non-null command argument")
            ),
            context: context,
            node: jsonValueNode
        )
    }

    private static func heistValue(_ value: Value) throws -> HeistValue {
        switch value {
        case .null:
            throw PublicJSONInputError("MCP arguments contains null")
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            return .int(int)
        case .double(let double):
            return .double(double)
        case .string(let string):
            return .string(string)
        case .data:
            throw PublicJSONInputError("MCP arguments contains binary data")
        case .array(let values):
            return .array(try values.map(heistValue))
        case .object(let object):
            return .object(try object.mapValues(heistValue))
        }
    }

    private static func jsonValueNode(_ value: Value) -> PublicJSONValueNode<Value> {
        switch value {
        case .null:
            return .null
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            return .int(int)
        case .double(let double):
            return .double(double)
        case .string(let string):
            return .string(string)
        case let .data(mimeType, data):
            return .data(mimeType: mimeType, byteCount: data.count)
        case .array(let values):
            return .array(values)
        case .object(let object):
            return .object(object)
        }
    }
}
