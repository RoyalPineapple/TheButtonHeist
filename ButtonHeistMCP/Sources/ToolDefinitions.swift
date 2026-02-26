import MCP
import ButtonHeist

enum ToolDefinitions {
    private static let supportedCommands = CommandCatalog.all.joined(separator: ", ")

    // NOTE: Video data handling
    // The MCP server intentionally omits raw base64 video data from responses.
    // Video payloads can be tens of megabytes which would overwhelm the MCP
    // context window. Instead, video metadata (dimensions, duration, frame count,
    // stop reason, interaction count) is returned as a JSON summary.
    //
    // Agents that need the actual video file should use the CLI instead:
    //   buttonheist session  →  stop_recording --output /path/to/file.mp4
    // Or pass the "output" parameter in stop_recording to write to disk and
    // receive only the file path in the response.

    static let run = Tool(
        name: "run",
        description: """
            Send one command through TheFence session orchestrator. \
            Supported commands: \(supportedCommands). \
            Note: screenshot data is returned inline as base64 PNG. \
            Video/recording data is summarized (metadata only) — raw video is too large for MCP. \
            Use the 'output' parameter with stop_recording to save video to a file path instead.
            """,
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
                "output": ["type": "string", "description": "File path to write screenshot/recording data to disk instead of returning inline"],
            ],
            "required": ["command"],
            "additionalProperties": true
        ]
    )
}
