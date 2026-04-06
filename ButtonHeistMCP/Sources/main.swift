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
        VoiceOver uses. You interact with live UI elements by their identity and traits, not \
        screen coordinates. A coordinate that works on one device breaks on another; \
        an element's label and traits work everywhere.

        ## Core Loop

        1. **See** — `get_interface` returns every visible element with a heistId, label, \
        value, traits, and actions.
        2. **Act** — `activate`, `type_text`, `scroll`, `swipe` — target by heistId or matcher.
        3. **Read the delta** — every action response reports what changed. If the delta \
        answers your question, skip the next `get_interface`.
        4. **Repeat** — only re-fetch when you need elements you haven't seen.

        ## Choosing Tools

        **Observing**: `get_interface` for element data, `get_screen` for visual context. \
        Start with `get_interface` — reach for `get_screen` only when layout or visual \
        state matters. Use `get_interface(full: true)` to discover off-screen content \
        inside scroll views.

        **Acting**: `activate` is your primary tool — it taps, toggles, follows links. \
        `type_text` for keyboard input. `swipe` for directional gestures. `scroll` for \
        paging through lists. Prefer `activate` over `gesture` — raw coordinates are \
        fragile and don't record well.

        **Finding**: `scroll_to_visible` when you've seen an element before but it scrolled \
        off-screen. `element_search` when you've never seen it — scrolls every container \
        looking for a match. `wait_for` when the element will appear asynchronously.

        **Composing**: `run_batch` for multi-step sequences in a single call. Attach \
        `expect` to each step for a self-verifying script.

        ## Expectations

        Every action is an opportunity to validate. Attaching `expect` costs nothing — \
        the action runs the same way — but turns a blind tap into a verified assertion. \
        Agents that use expectations routinely catch regressions as a side effect of \
        navigation. Agents that don't are just clicking and hoping.

        Before you act, ask: what should change? A toggle flips a value. A nav button \
        changes the screen. A delete removes an element. Form that hypothesis, attach it, \
        and let the result confirm or correct you. Unmet expectations are information, \
        not errors — they tell you what actually happened so you can adapt.

        Expectations are as specific as you need — say what you know, omit what you don't: \
        `"elements_changed"` — something should change (broadest). \
        `{"elementUpdated": {}}` — some element's property should change. \
        `{"elementUpdated": {"heistId": "counter"}}` — this specific element should change. \
        `{"elementUpdated": {"heistId": "counter", "property": "value"}}` — its value specifically. \
        `{"elementUpdated": {"heistId": "counter", "newValue": "5"}}` — and it should become "5". \
        Each level narrows what counts as success. The more specific, the more a failure tells you.

        ## Recording Heists

        `start_heist` / `stop_heist` capture your session as a replayable .heist file. \
        The recording is automatic — every successful action becomes a step — but the \
        quality depends entirely on how you approach it.

        **Prime the interface first.** Call `get_interface` before your first action. \
        The recorder converts heistIds to portable matchers behind the scenes, but needs \
        cached element data to do it well.

        **Attach expectations to every meaningful action.** Expectations are recorded \
        with the step. A heist without expectations is a sequence of taps; a heist with \
        expectations is a self-verifying test suite that validates on every replay.

        **One action, one purpose.** Each step should do exactly one thing and verify it. \
        Don't chain five taps and check at the end — check after each one. This makes \
        replay failures precise: step 7 failed means the 7th interaction broke.

        **Read the delta before moving on.** If your expectation wasn't met, understand \
        why before continuing. The recording only captures successful actions — continuing \
        after a missed expectation means the heist may not replay the same way.

        ## Efficiency

        Read the delta first — skip `get_interface` when the delta already told you what \
        changed. Use heistIds on the current screen, matchers after navigation. Batch \
        predictable sequences. Escalate progressively: `get_interface` → filtered → \
        `full: true`.
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
                 "scroll", "scroll_to_visible", "element_search", "scroll_to_edge",
                 "edit_action", "dismiss_keyboard",
                 "run_batch", "get_session_state",
                 "connect", "list_targets",
                 "get_session_log", "archive_session",
                 "start_heist", "stop_heist", "play_heist":
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
