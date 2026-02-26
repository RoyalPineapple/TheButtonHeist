import Foundation
import MCP
import ButtonHeist

@main
struct ButtonHeistMCPServer {
    static func main() async throws {
        let fence = TheFence(
            configuration: .init(
                deviceFilter: ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"],
                connectionTimeout: 30,
                forceSession: ProcessInfo.processInfo.environment["BUTTONHEIST_FORCE"] == "1",
                token: ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"],
                autoReconnect: true
            )
        )

        let server = Server(
            name: "buttonheist",
            version: buttonHeistVersion,
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [ToolDefinitions.run])
        }

        await server.withMethodHandler(CallTool.self) { params in
            await handleToolCall(params, fence: fence)
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }

    @MainActor
    private static func handleToolCall(
        _ params: CallTool.Parameters,
        fence: TheFence
    ) async -> CallTool.Result {
        guard params.name == "run" else {
            return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
        }

        do {
            let request = try decodeArguments(params.arguments)
            guard let command = request["command"] as? String else {
                return .init(content: [.text("Missing required parameter: command")], isError: true)
            }

            if let validationError = validateArgs(command: command, args: request) {
                return .init(content: [.text(validationError)], isError: true)
            }

            let response = try await fence.execute(request: request)
            return try renderResponse(response)
        } catch {
            return .init(content: [.text(errorMessage(error))], isError: true)
        }
    }

    // MARK: - Per-command argument validation
    // Validates required parameters before dispatching to TheFence, so callers
    // get a clear error message immediately instead of a generic dispatch failure.

    private static func validateArgs(command: String, args: [String: Any]) -> String? {
        // Commands that require an element target (identifier or order)
        let needsTarget: Set<String> = ["tap", "activate", "increment", "decrement", "perform_custom_action"]

        if needsTarget.contains(command) {
            let hasIdentifier = args["identifier"] is String
            let hasOrder = args["order"] != nil
            let hasCoordinates = args["x"] != nil && args["y"] != nil

            // tap can use coordinates instead of an element target
            if command == "tap" && (hasIdentifier || hasOrder || hasCoordinates) {
                return nil
            }

            if !hasIdentifier && !hasOrder {
                return "Missing required parameter for '\(command)': provide 'identifier' (accessibility identifier) or 'order' (element index). Run get_interface first to discover available elements."
            }
        }

        // type_text needs at least text or deleteCount
        if command == "type_text" {
            let hasText = args["text"] is String
            let hasDeleteCount = args["deleteCount"] != nil
            if !hasText && !hasDeleteCount {
                return "Missing required parameter for 'type_text': provide 'text', 'deleteCount', or both."
            }
        }

        // swipe: if using coordinates, need start and end points
        // (direction-based swipe on an element is handled by TheFence)

        // drag requires endX and endY
        if command == "drag" {
            if args["endX"] == nil || args["endY"] == nil {
                return "Missing required parameters for 'drag': 'endX' and 'endY' are required."
            }
        }

        // pinch requires scale
        if command == "pinch" {
            if args["scale"] == nil {
                return "Missing required parameter for 'pinch': 'scale' is required."
            }
        }

        // rotate requires angle
        if command == "rotate" {
            if args["angle"] == nil {
                return "Missing required parameter for 'rotate': 'angle' is required."
            }
        }

        // perform_custom_action requires actionName
        if command == "perform_custom_action" {
            if !(args["actionName"] is String) {
                return "Missing required parameter for 'perform_custom_action': 'actionName' is required."
            }
        }

        // edit_action requires action
        if command == "edit_action" {
            if !(args["action"] is String) {
                return "Missing required parameter for 'edit_action': 'action' is required (copy, paste, cut, select, selectAll)."
            }
        }

        return nil
    }

    private static func decodeArguments(_ arguments: [String: Value]?) throws -> [String: Any] {
        guard let arguments else { return [:] }
        var request: [String: Any] = [:]
        for (key, value) in arguments {
            request[key] = anyValue(from: value)
        }
        return request
    }

    private static func anyValue(from value: Value) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .int(let int):
            return int
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .data(_, let data):
            return data.base64EncodedString()
        case .array(let values):
            return values.map(anyValue(from:))
        case .object(let object):
            var result: [String: Any] = [:]
            for (key, nested) in object {
                result[key] = anyValue(from: nested)
            }
            return result
        }
    }

    // Video data is intentionally replaced with a size summary rather than passed through.
    // Raw base64 video payloads can be tens of megabytes, which would overwhelm the MCP
    // context window. Agents that need the actual file should pass "output" to stop_recording,
    // or use the CLI directly: `buttonheist session` → `stop_recording --output /path/to/file.mp4`
    private static func renderResponse(_ response: FenceResponse) throws -> CallTool.Result {
        var content: [Tool.Content] = []
        var payload = response.jsonDict() ?? [:]

        if let pngData = payload["pngData"] as? String {
            content.append(.image(data: pngData, mimeType: "image/png", metadata: nil))
            payload["pngData"] = "<omitted base64 png data>"
        }

        if let videoData = payload["videoData"] as? String {
            payload["videoData"] = "<omitted base64 video data (\(videoData.count) chars)>"
        }

        let isError = (payload["status"] as? String) == "error"
        content.append(.text(try compactJSON(payload)))
        return .init(content: content, isError: isError)
    }

    private static func compactJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func errorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
