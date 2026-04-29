import Foundation
import MCP
import ButtonHeist
import TheScore

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
        2. **Act** — `activate`, `type_text`, `scroll`, `gesture` — target by heistId or matcher. \
        Always attach `expect` when you know what should change.
        3. **Read the response** — every response tells you two things: what your action did \
        (`interfaceDelta`) and what changed while you were thinking (`[background: ...]`). \
        If either answers your question, skip `get_interface`.
        4. **Wait if needed** — when the delta shows a transient state (spinner, loading overlay) \
        and your expectation wasn't met, call `wait_for_change` with the same expectation. \
        The server rides through intermediate states and returns when the real change lands. \
        If the change already happened in the background, `wait_for_change` returns instantly.
        5. **Repeat** — only re-fetch when you need elements you haven't seen.

        ## Choosing Tools

        **Observing**: `get_interface` for element data, `get_screen` for visual context. \
        Start with `get_interface` — it explores the full screen by default, including \
        off-screen content in scroll views. Reach for `get_screen` only when layout or \
        visual state matters.

        **Acting**: `activate` is your primary tool — it taps, toggles, follows links. \
        `type_text` for keyboard input. `gesture` with type "swipe" for directional gestures. \
        `scroll` for paging through lists. Prefer `activate` over `gesture` — raw coordinates \
        are fragile and don't record well.

        **Finding**: `scroll` with mode "to_visible" when you've seen an element before but it \
        scrolled off-screen. `scroll` with mode "search" when you've never seen it — scrolls \
        every container looking for a match. `wait_for` when you know a specific element will appear.

        **Waiting**: `wait_for_change` when the UI is updating asynchronously — network \
        requests, timers, animations completing. Pass an expectation to wait for the specific \
        outcome: `expect="screen_changed"` rides through loading spinners until the real \
        navigation happens. With no expectation, returns on any tree change. This is the \
        correct response when your action produced a transient state (spinner appeared, \
        interactive elements disappeared) and you need the final result.

        **Composing**: `run_batch` for multi-step sequences in a single call. Attach \
        `expect` to each step for inline verification.

        ## The Server Is Always Watching

        Every response includes what changed since your last call. You never poll. Three \
        things can happen between your tool calls:

        **Nothing changed** — no `[background]` line, your heistIds are still valid, proceed.

        **Elements changed** — `[background: elements changed +2 -1 (15 total)]` with the \
        added/removed elements listed. Your heistIds are still valid. The delta shows what's new.

        **Screen changed** — `[background: screen changed (7 elements)]` with the full new \
        element list. Your heistIds are stale. Don't try to use them — read the new elements \
        from the background block. If you had an `expect` on your action and it matches the \
        background change, the action is skipped entirely and you get "expectation already met."  \
        If you didn't have an expect, the action is skipped with "Screen changed while you were \
        thinking" and the response carries the new interface. Either way, you're never left \
        pointing at a screen that doesn't exist.

        **Async pattern** — for operations that take time (payments, network requests):
        1. `activate pay_button expect="screen_changed"` — tap and declare intent
        2. Delta shows spinner, expectation not met → `wait_for_change expect="screen_changed"` \
        — server waits until the real screen arrives
        3. Or: you were slow to act, payment already completed → your next call gets the \
        confirmation instantly via background awareness. No wait needed.

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
        `{"type": "element_updated"}` — some element's property should change. \
        `{"type": "element_updated", "heistId": "counter"}` — this specific element should change. \
        `{"type": "element_updated", "heistId": "counter", "property": "value"}` — its value specifically. \
        `{"type": "element_updated", "heistId": "counter", "newValue": "5"}` — and it should become "5". \
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
        changed. Use heistIds on the current screen, matchers after navigation. Filter \
        with matcher fields or heistId lists when you only need a subset of elements.
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
            case "get_interface", "activate", "type_text", "get_screen",
                 "wait_for_change", "wait_for", "start_recording", "stop_recording", "list_devices",
                 "set_pasteboard", "get_pasteboard",
                 "run_batch", "get_session_state",
                 "connect", "list_targets",
                 "get_session_log", "archive_session",
                 "start_heist", "stop_heist", "play_heist":
                request["command"] = params.name

            // Grouped gesture tool — "type" field becomes the command
            case "gesture":
                guard let type = request.removeValue(forKey: "type") as? String else {
                    return .init(content: [.text(text: "Missing required parameter: type", annotations: nil, _meta: nil)], isError: true)
                }
                request["command"] = type

            // Grouped scroll tool — "mode" field selects the TheFence command
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
                    return .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
                }

            // edit_action routes "dismiss" to dismiss_keyboard
            case "edit_action":
                if let action = request["action"] as? String, action == "dismiss" {
                    request.removeValue(forKey: "action")
                    request["command"] = "dismiss_keyboard"
                } else {
                    request["command"] = "edit_action"
                }

            default:
                return .init(content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)], isError: true)
            }

            let response = try await fence.execute(request: request)
            idleMonitor.resetTimer()
            let backgroundDelta = fence.drainBackgroundDelta()
            return try renderResponse(response, backgroundDelta: backgroundDelta)
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
    private static func renderResponse(_ response: FenceResponse, backgroundDelta: InterfaceDelta? = nil) throws -> CallTool.Result {
        var content: [Tool.Content] = []

        // Background changes: what happened while the agent was thinking
        if let backgroundDelta, backgroundDelta.kind != .noChange {
            var lines: [String] = []
            switch backgroundDelta.kind {
            case .screenChanged:
                lines.append("[background: screen changed (\(backgroundDelta.elementCount) elements)]")
                if let elements = backgroundDelta.newInterface?.elements {
                    for (index, element) in elements.enumerated() {
                        lines.append("  [\(index)] \(Self.compactBackgroundElement(element))")
                    }
                }
            case .elementsChanged:
                var parts: [String] = []
                if let added = backgroundDelta.added { parts.append("+\(added.count)") }
                if let removed = backgroundDelta.removed { parts.append("-\(removed.count)") }
                if let updated = backgroundDelta.updated { parts.append("~\(updated.count)") }
                lines.append("[background: elements changed \(parts.joined(separator: " ")) (\(backgroundDelta.elementCount) total)]")
                if let added = backgroundDelta.added {
                    for element in added { lines.append("  + \(element.heistId) \"\(element.label ?? "")\"") }
                }
                if let removed = backgroundDelta.removed {
                    for heistId in removed { lines.append("  - \(heistId)") }
                }
            case .noChange:
                break
            }
            if !lines.isEmpty {
                content.append(.text(text: lines.joined(separator: "\n"), annotations: nil, _meta: nil))
            }
        }

        // Screenshots: embed as image content
        if case .screenshotData(let pngData, _, _) = response {
            content.append(.image(data: pngData, mimeType: "image/png", annotations: nil, _meta: nil))
        } else if case .screenshot = response {
            // File-based screenshot — handled by compact text below
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
