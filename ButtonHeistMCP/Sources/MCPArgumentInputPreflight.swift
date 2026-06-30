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
        try MCPValueBridge.commandEnvelope(from: arguments)
    }
}
