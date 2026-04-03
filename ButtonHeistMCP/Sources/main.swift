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

    // MARK: - Agent Instructions
    //
    // Injected into the MCP initialize response as session-level guidance.
    // Covers: mental model, core loop, targeting rules, delta interpretation,
    // and efficiency patterns. Per-tool details live in ToolDefinitions.swift.

    static let instructions = """
        Button Heist drives iOS apps through the accessibility layer — the same interface \
        VoiceOver uses. You interact with live UI elements by identity and traits, not \
        screen coordinates. Every control knows what it is, what state it's in, and how \
        to activate it. A coordinate that worked on one device is wrong on another; \
        an element's label or traits work everywhere.

        ## Core Loop

        1. See the screen: `get_interface` returns every visible element with a heistId, \
        label, value, traits, and available actions.
        2. Act on an element: `activate`, `type_text`, `scroll`, or `swipe` — target by heistId or matcher.
        3. Read the delta: every action response reports what changed (+added, -removed, ~updated). \
        If the screen navigated, the delta includes the complete new interface.
        4. Repeat. Only call `get_interface` again when you need to discover elements not in the delta.

        ## Targeting Rules

        **heistId**: Use it when you've seen the element in a `get_interface` response or action delta. \
        Stable on the current screen, zero ambiguity. After a screen change (navigation, modal, tab switch), \
        all previous heistIds are invalid — use what the delta's new interface gave you.

        **Matcher** (label, identifier, value, traits): Use when you haven't seen the element yet, \
        after a screen transition, or in `wait_for`/`scroll_to_visible`. Strings match as \
        case-insensitive substrings. Traits match exactly. If zero elements match, you get a miss \
        with suggestions — never a fuzzy guess.

        Never construct or predict a heistId. Never carry one across screen transitions.

        ## Reading Deltas

        Every action response includes a delta:
        - `+ heistId "label" [traits]` — element appeared
        - `- heistId` — element disappeared
        - `~ heistId: property "old" → "new"` — property changed
        - `screen changed` — full navigation; new interface included, all old heistIds are gone

        If the delta answers your question, skip the `get_interface` call.

        ## Expectations

        Attach `expect` to any action to declare what should happen. The action still executes regardless; \
        the result tells you whether your expectation was met.
        - `"elements_changed"` — something visible should change
        - `"screen_changed"` — a navigation/modal should occur
        - `{"elementUpdated": {"heistId": "x", "property": "value", "newValue": "5"}}` — specific check \
        (all fields optional, omitted = wildcard)

        Unmet expectations are information, not errors — you decide what to do. \
        Use expectations to investigate: if you're unsure what a control does, activate it with \
        an expectation and let the result confirm or refute your hypothesis. The delta tells you \
        what actually happened either way.

        ## Batching

        `run_batch` sends multiple commands in one call. Use `stop_on_error` (default) for dependent \
        sequences, `continue_on_error` for independent steps. The response includes per-step results \
        and a merged net delta across all steps.

        Combine batching with expectations to build a deterministic test suite on the fly. A batch \
        with expectations on every step is a self-verifying script — each step declares its hypothesis, \
        the system checks it against the real outcome, and the summary tells you exactly which steps \
        passed and which diverged. You can construct these dynamically from what you learned in \
        `get_interface`, run them, and have a complete pass/fail report in a single round trip.

        ## Efficiency

        - **Don't over-fetch**: read the delta first, call `get_interface` only when you need elements \
        you haven't seen.
        - **HeistIds on this screen, matchers across screens**: after navigation, switch to matchers \
        or read from the delta's new interface.
        - **Batch predictable sequences**: form fills, navigation flows — fewer round trips, cleaner signal.
        - **Progressive disclosure**: `get_interface` (visible) → filtered by traits/label → `full: true` \
        (scroll-discovered). Escalate only when the cheaper option isn't enough.
        - **Expectations as guard rails**: attach them to actions with a clear hypothesis. They cost \
        nothing when met and surface problems immediately when not.
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
            return try renderResponse(response)
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
}
