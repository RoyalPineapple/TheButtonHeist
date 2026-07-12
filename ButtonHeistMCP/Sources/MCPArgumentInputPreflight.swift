import Foundation
import MCP
@_spi(ButtonHeistTooling) import ButtonHeist

typealias MCPRawArgumentObject = [String: Value]

struct MCPToolRequest {
    let name: String
    let arguments: TheFence.CommandArgumentEnvelope

    init(name: String, arguments: MCPRawArgumentObject?) throws {
        self.name = name
        self.arguments = try MCPValueBridge.commandEnvelope(from: arguments)
    }
}
