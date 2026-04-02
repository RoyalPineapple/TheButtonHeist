import Foundation
import MCP
import ButtonHeist

@main
struct ButtonHeistMCPServer {
    static func main() async throws {
        let (fence, idleMonitor) = await setUp()

        let server = Server(
            name: "buttonheist",
            version: buttonHeistVersion,
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: ToolDefinitions.all)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await handleToolCall(params, fence: fence, idleMonitor: idleMonitor)
        }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }

    @ButtonHeistActor
    private static func setUp() -> (TheFence, IdleMonitor) {
        let config = EnvironmentConfig.resolve()
        let fence = TheFence(configuration: config.fenceConfiguration)
        let idleMonitor = IdleMonitor(timeout: config.sessionTimeout) { [fence] in
            fence.stop()
        }
        return (fence, idleMonitor)
    }

    @ButtonHeistActor
    private static func handleToolCall(
        _ params: CallTool.Parameters,
        fence: TheFence,
        idleMonitor: IdleMonitor
    ) async -> CallTool.Result {
        do {
            var request = try decodeArguments(params.arguments)

            // Route tool name → TheFence command
            switch params.name {
            // Direct 1:1 tools — tool name IS the command
            case "get_interface", "activate", "type_text", "swipe", "get_screen",
                 "wait_for_idle", "wait_for", "start_recording", "stop_recording", "list_devices",
                 "set_pasteboard", "get_pasteboard",
                 "scroll", "scroll_to_visible", "scroll_to_edge",
                 "edit_action", "dismiss_keyboard",
                 "run_batch", "get_session_state",
                 "connect", "list_targets",
                 "get_session_log", "archive_session":
                request["command"] = params.name

            // Grouped tool — "type" field becomes the command
            case "gesture":
                guard let type = request.removeValue(forKey: "type") as? String else {
                    return .init(content: [.text(text: "Missing required parameter: type", annotations: nil, _meta: nil)], isError: true)
                }
                request["command"] = type

            default:
                return .init(content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)], isError: true)
            }

            let response = try await fence.execute(request: request)
            idleMonitor.resetTimer()
            return try renderResponse(response, fence: fence)
        } catch {
            idleMonitor.resetTimer()
            return .init(content: [.text(text: error.displayMessage, annotations: nil, _meta: nil)], isError: true)
        }
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
    @ButtonHeistActor
    private static func renderResponse(_ response: FenceResponse, fence: TheFence) throws -> CallTool.Result {
        var content: [Tool.Content] = []

        // Screenshots: embed as image content
        if case .screenshotData(let pngData, _, _) = response {
            content.append(.image(data: pngData, mimeType: "image/png", annotations: nil, _meta: nil))
        } else if case .screenshot = response {
            // File-based screenshot — handled by compact text below
        }

        let isError: Bool
        if case .error = response {
            isError = true
        } else if case .action(let result, _) = response, !result.success {
            isError = true
        } else {
            isError = false
        }

        let text = fence.applyTelemetry(to: response.compactFormatted())
        content.append(.text(text: text, annotations: nil, _meta: nil))
        return .init(content: content, isError: isError)
    }
}
