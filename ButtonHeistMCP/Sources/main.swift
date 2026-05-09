import Foundation
import MCP
import ButtonHeist
import TheScore

@main
struct ButtonHeistMCPServer {
    struct ToolRoutingError: Error, Equatable {
        let message: String
    }

    static func main() async throws {
        let (fence, idleMonitor) = await setUp()

        let server = Server(
            name: "buttonheist",
            version: buttonHeistVersion,
            instructions: Self.instructions,
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

    static let instructions = """
        Button Heist drives iOS apps through the accessibility layer — the same interface \
        VoiceOver uses. Target elements by heistId, label, value, and traits, not by screen \
        coordinates. The core loop is: `get_interface` to see, then `activate`/`type_text`/\
        `scroll`/`gesture` to act with an `expect` attached. Every response carries a \
        `[background: ...]` block describing what changed since your last call — read it \
        before deciding to re-fetch. When an action produces a transient state (spinner, \
        loading overlay), call `wait_for_change` with the same expectation to ride through \
        intermediate states. Use `run_batch` for multi-step sequences with per-step expects. \
        Use `start_heist`/`stop_heist` to record replayable .heist files. \
        Full guide: docs/MCP-AGENT-GUIDE.md.
        """

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
        defer { idleMonitor.resetTimer() }
        do {
            let arguments = try decodeArguments(params.arguments)
            let routed = routeToolRequest(name: params.name, arguments: arguments)
            let request: [String: Any]
            switch routed {
            case .success(let value):
                request = value
            case .failure(let error):
                return .init(content: [.text(text: error.message, annotations: nil, _meta: nil)], isError: true)
            }

            let response = try await fence.execute(request: request)
            let backgroundDeltas = fence.drainBackgroundDeltas()
            return try renderResponse(response, backgroundDeltas: backgroundDeltas)
        } catch {
            return .init(content: [.text(text: error.displayMessage, annotations: nil, _meta: nil)], isError: true)
        }
    }

    static func routeToolRequest(
        name: String,
        arguments: [String: Any]
    ) -> Result<[String: Any], ToolRoutingError> {
        var request = arguments

        // Direct 1:1 tools — tool name IS the command.
        switch name {
        case "get_interface", "activate", "type_text", "get_screen",
             "wait_for_change", "wait_for", "start_recording", "stop_recording", "list_devices",
             "set_pasteboard", "get_pasteboard",
             "run_batch", "get_session_state",
             "connect", "list_targets",
             "get_session_log", "archive_session",
             "start_heist", "stop_heist", "play_heist":
            request["command"] = name
            return .success(request)

        case "gesture":
            guard let type = request.removeValue(forKey: "type") as? String else {
                return .failure(ToolRoutingError(message: "Missing required parameter: type"))
            }
            request["command"] = type
            return .success(request)

        case "scroll":
            let mode = (request.removeValue(forKey: "mode") as? String) ?? "page"
            switch mode {
            case "page":
                request["command"] = "scroll"
            case "to_visible":
                request["command"] = "scroll_to_visible"
            case "search":
                request["command"] = "element_search"
            case "to_edge":
                request["command"] = "scroll_to_edge"
            default:
                let message = "Unknown scroll mode: \(mode). Valid: page, to_visible, search, to_edge"
                return .failure(ToolRoutingError(message: message))
            }
            return .success(request)

        case "edit_action":
            if let action = request["action"] as? String, action == "dismiss" {
                request.removeValue(forKey: "action")
                request["command"] = "dismiss_keyboard"
            } else {
                request["command"] = "edit_action"
            }
            return .success(request)

        default:
            return .failure(ToolRoutingError(message: "Unknown tool: \(name)"))
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

    static func renderResponse(_ response: FenceResponse, backgroundDeltas: [InterfaceDelta]) throws -> CallTool.Result {
        var content: [Tool.Content] = []

        // Background changes: what happened while the agent was thinking
        for backgroundDelta in backgroundDeltas {
            // Skip silent no-change deltas; keep transient-bearing ones since
            // those describe activity the agent should know about.
            if case .noChange(let payload) = backgroundDelta, payload.transient.isEmpty {
                continue
            }
            let transient = backgroundDelta.transient
            var lines: [String] = []
            switch backgroundDelta {
            case .screenChanged(let payload):
                lines.append("[background: screen changed (\(payload.elementCount) elements)]")
                for (index, element) in payload.newInterface.elements.enumerated() {
                    lines.append("  [\(index)] \(Self.compactBackgroundElement(element))")
                }
                for element in transient {
                    lines.append("  +- \(Self.compactBackgroundElement(element))")
                }
            case .elementsChanged(let payload):
                let edits = payload.edits
                var parts: [String] = []
                if !edits.added.isEmpty { parts.append("+\(edits.added.count)") }
                if !edits.removed.isEmpty { parts.append("-\(edits.removed.count)") }
                if !edits.updated.isEmpty { parts.append("~\(edits.updated.count)") }
                if !transient.isEmpty { parts.append("+-\(transient.count)") }
                lines.append("[background: elements changed \(parts.joined(separator: " ")) (\(payload.elementCount) total)]")
                for element in edits.added {
                    lines.append("  + \(element.heistId) \"\(element.label ?? "")\"")
                }
                for heistId in edits.removed {
                    lines.append("  - \(heistId)")
                }
                for element in transient {
                    lines.append("  +- \(Self.compactBackgroundElement(element))")
                }
            case .noChange(let payload):
                lines.append("[background: no net change (\(payload.elementCount) elements)]")
                for element in transient {
                    lines.append("  +- \(Self.compactBackgroundElement(element))")
                }
            }
            if !lines.isEmpty {
                content.append(.text(text: lines.joined(separator: "\n"), annotations: nil, _meta: nil))
            }
        }

        // Screenshots: embed as image content. File-based screenshots fall through
        // to the compact text below.
        if case .screenshotData(let pngData, _, _) = response {
            content.append(.image(data: pngData, mimeType: "image/png", annotations: nil, _meta: nil))
        }

        content.append(.text(text: response.compactFormatted(), annotations: nil, _meta: nil))
        return .init(content: content, isError: response.isFailure)
    }

    private static func compactBackgroundElement(_ element: HeistElement) -> String {
        var parts = [element.heistId]
        if let label = element.label { parts.append("\"\(label)\"") }
        if !element.traits.isEmpty {
            let traitNames = element.traits.map(\.rawValue)
            parts.append("[\(traitNames.joined(separator: ", "))]")
        }
        return parts.joined(separator: " ")
    }
}
