import Foundation
import MCP
import ButtonHeist

/// Idle timeout before disconnecting from the device (seconds).
/// `BUTTONHEIST_SESSION_TIMEOUT` env var overrides the default.
private let sessionTimeout: TimeInterval = {
    if let envValue = ProcessInfo.processInfo.environment["BUTTONHEIST_SESSION_TIMEOUT"],
       let parsed = Double(envValue), parsed > 0 {
        return parsed
    }
    return 60.0
}()

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
        let fence = TheFence(
            configuration: .init(
                deviceFilter: ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"],
                connectionTimeout: 30,
                token: ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"],
                autoReconnect: true
            )
        )
        let idleMonitor = IdleMonitor(fence: fence, timeout: sessionTimeout)
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
                 "wait_for_idle", "start_recording", "stop_recording", "list_devices",
                 "scroll", "scroll_to_visible", "scroll_to_edge",
                 "run_batch", "get_session_state":
                request["command"] = params.name

            // Grouped tools — "type" field becomes the command
            case "gesture":
                guard let type = request.removeValue(forKey: "type") as? String else {
                    return .init(content: [.text(text: "Missing required parameter: type", annotations: nil, _meta: nil)], isError: true)
                }
                request["command"] = type

            case "accessibility_action":
                guard let type = request.removeValue(forKey: "type") as? String else {
                    return .init(content: [.text(text: "Missing required parameter: type", annotations: nil, _meta: nil)], isError: true)
                }
                request["command"] = type

            default:
                return .init(content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)], isError: true)
            }

            let response = try await fence.execute(request: request)
            idleMonitor.resetTimer()
            return try renderResponse(response)
        } catch {
            idleMonitor.resetTimer()
            return .init(content: [.text(text: errorMessage(error), annotations: nil, _meta: nil)], isError: true)
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
    private static func renderResponse(_ response: FenceResponse) throws -> CallTool.Result {
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

        content.append(.text(text: response.compactFormatted(), annotations: nil, _meta: nil))
        return .init(content: content, isError: isError)
    }

    private static func errorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

// MARK: - Idle Timeout

/// Disconnects the fence after a period of inactivity.
/// The next tool call will auto-reconnect via `TheFence.execute()`.
@ButtonHeistActor
private final class IdleMonitor {
    private let fence: TheFence
    private let timeout: TimeInterval
    private var timeoutTask: Task<Void, Never>?

    init(fence: TheFence, timeout: TimeInterval) {
        self.fence = fence
        self.timeout = timeout
    }

    func resetTimer() {
        timeoutTask?.cancel()
        guard timeout > 0 else { return }
        timeoutTask = Task { [weak self, timeout] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self else { return }
            self.fence.stop()
        }
    }
}
