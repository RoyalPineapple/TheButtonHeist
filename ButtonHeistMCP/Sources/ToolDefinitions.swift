import MCP
import ButtonHeist

enum ToolDefinitions {
    private static let supportedCommands = MastermindCommandCatalog.all.joined(separator: ", ")

    static let run = Tool(
        name: "run",
        description: "Send one command through TheMastermind session orchestrator. Supported commands: \(supportedCommands)",
        inputSchema: [
            "type": "object",
            "properties": [
                "command": ["type": "string", "description": "CLI session command (get_interface, tap, type_text, get_screen, ...)"],
                "id": ["type": "string", "description": "Optional request id echoed in the response"],
                "identifier": ["type": "string", "description": "Target accessibility identifier"],
                "order": ["type": "integer", "description": "Target element order index"],
                "x": ["type": "number"],
                "y": ["type": "number"],
                "text": ["type": "string"],
                "output": ["type": "string", "description": "Optional output path for screenshot/recording data"],
            ],
            "required": ["command"],
            "additionalProperties": true
        ]
    )
}
