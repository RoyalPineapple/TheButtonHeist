import Testing
@testable import ButtonHeistMCP
import ButtonHeist

struct ToolRoutingTests {

    @Test("direct tools route to same command")
    func directToolRoutesToSameCommand() throws {
        let request = try routed("start_heist", ["identifier": "demo"])

        #expect(request["command"] as? String == "start_heist")
        #expect(request["identifier"] as? String == "demo")
    }

    @Test("gesture type routes to command and removes type")
    func gestureTypeRoutesToCommand() throws {
        let request = try routed("gesture", ["type": "swipe", "direction": "left"])

        #expect(request["command"] as? String == "swipe")
        #expect(request["type"] == nil)
        #expect(request["direction"] as? String == "left")
    }

    @Test("gesture requires type")
    func gestureRequiresType() {
        let result = ButtonHeistMCPServer.routeToolRequest(name: "gesture", arguments: [:])

        guard case .failure(let error) = result else {
            Issue.record("Expected routing failure")
            return
        }
        #expect(error.message == "schema validation failed for type: observed missing; expected enum one of one_finger_tap, long_press, swipe, drag, pinch, rotate, two_finger_tap, draw_path, draw_bezier")
    }

    @Test("scroll modes route to concrete commands")
    func scrollModesRouteToConcreteCommands() throws {
        let cases: [(mode: String?, command: String)] = [
            (nil, "scroll"),
            ("page", "scroll"),
            ("to_visible", "scroll_to_visible"),
            ("search", "element_search"),
            ("to_edge", "scroll_to_edge"),
        ]

        for routeCase in cases {
            var arguments: [String: Any] = ["direction": "down"]
            if let mode = routeCase.mode {
                arguments["mode"] = mode
            }
            let request = try routed("scroll", arguments)

            #expect(request["command"] as? String == routeCase.command)
            #expect(request["mode"] == nil)
            #expect(request["direction"] as? String == "down")
        }
    }

    @Test("scroll rejects unknown mode")
    func scrollRejectsUnknownMode() {
        let result = ButtonHeistMCPServer.routeToolRequest(
            name: "scroll",
            arguments: ["mode": "sideways"]
        )

        guard case .failure(let error) = result else {
            Issue.record("Expected routing failure")
            return
        }
        #expect(error.message == "schema validation failed for mode: observed string \"sideways\"; expected enum one of page, to_visible, search, to_edge")
    }

    @Test("edit_action dismiss routes to dismiss_keyboard")
    func editActionDismissRoutesToDismissKeyboard() throws {
        let request = try routed("edit_action", ["action": "dismiss"])

        #expect(request["command"] as? String == "dismiss_keyboard")
        #expect(request["action"] == nil)
    }

    @Test("edit_action keeps standard edit actions")
    func editActionKeepsStandardEditActions() throws {
        let request = try routed("edit_action", ["action": "copy"])

        #expect(request["command"] as? String == "edit_action")
        #expect(request["action"] as? String == "copy")
    }

    @Test("run_batch routes nested MCP tool shapes")
    func runBatchRoutesNestedMCPToolShapes() throws {
        let steps = try normalizeBatchSteps([
            ["command": "gesture", "type": "swipe", "direction": "left"],
            ["command": "scroll", "mode": "search", "label": "Done"],
            ["command": "edit_action", "action": "dismiss"],
        ])

        #expect(steps[0]["command"] as? String == "swipe")
        #expect(steps[0]["type"] == nil)
        #expect(steps[0]["direction"] as? String == "left")
        #expect(steps[1]["command"] as? String == "element_search")
        #expect(steps[1]["mode"] == nil)
        #expect(steps[1]["label"] as? String == "Done")
        #expect(steps[2]["command"] as? String == "dismiss_keyboard")
        #expect(steps[2]["action"] == nil)
    }

    @Test("run_batch still accepts raw Fence command shapes")
    func runBatchAcceptsRawFenceCommandShapes() throws {
        let steps = try normalizeBatchSteps([
            ["command": "swipe", "direction": "right"],
            ["command": "scroll_to_visible", "heistId": "element-1"],
            ["command": "dismiss_keyboard"],
        ])

        #expect(steps[0]["command"] as? String == "swipe")
        #expect(steps[0]["direction"] as? String == "right")
        #expect(steps[1]["command"] as? String == "scroll_to_visible")
        #expect(steps[1]["heistId"] as? String == "element-1")
        #expect(steps[2]["command"] as? String == "dismiss_keyboard")
    }

    @Test("batch step normalization reports nested routing errors")
    func batchStepNormalizationReportsNestedRoutingErrors() {
        let result = FenceOperationCatalog.normalizeBatchStep(["command": "gesture"])

        guard case .failure(let error) = result else {
            Issue.record("Expected routing failure")
            return
        }
        #expect(error.message == "schema validation failed for type: observed missing; expected enum one of one_finger_tap, long_press, swipe, drag, pinch, rotate, two_finger_tap, draw_path, draw_bezier")
    }

    @Test("top-level raw grouped commands report canonical grouped tool shape")
    func topLevelRawGroupedCommandsReportCanonicalGroupedToolShape() {
        let cases: [(toolName: String, message: String)] = [
            (
                "swipe",
                "Tool \"swipe\" is grouped under \"gesture\"; call gesture with type=\"swipe\"."
            ),
            (
                "scroll_to_visible",
                "Tool \"scroll_to_visible\" is grouped under \"scroll\"; call scroll with mode=\"to_visible\"."
            ),
            (
                "element_search",
                "Tool \"element_search\" is grouped under \"scroll\"; call scroll with mode=\"search\"."
            ),
            (
                "scroll_to_edge",
                "Tool \"scroll_to_edge\" is grouped under \"scroll\"; call scroll with mode=\"to_edge\"."
            ),
            (
                "dismiss_keyboard",
                "Tool \"dismiss_keyboard\" is grouped under \"edit_action\"; call edit_action with action=\"dismiss\"."
            ),
        ]

        for routeCase in cases {
            let result = ButtonHeistMCPServer.routeToolRequest(name: routeCase.toolName, arguments: [:])
            guard case .failure(let error) = result else {
                Issue.record("Expected top-level routing failure for \(routeCase.toolName)")
                continue
            }
            #expect(error.message == routeCase.message)
        }
    }

    @Test("raw grouped commands stay accepted in batch")
    func rawGroupedCommandsStayAcceptedInBatch() throws {
        let steps = try normalizeBatchSteps([
            ["command": "swipe", "direction": "up"],
            ["command": "scroll_to_visible", "heistId": "element-1"],
            ["command": "element_search", "label": "Done"],
            ["command": "scroll_to_edge", "heistId": "scroll-view", "edge": "bottom"],
            ["command": "dismiss_keyboard"],
        ])

        #expect(steps[0]["command"] as? String == "swipe")
        #expect(steps[0]["direction"] as? String == "up")
        #expect(steps[1]["command"] as? String == "scroll_to_visible")
        #expect(steps[1]["heistId"] as? String == "element-1")
        #expect(steps[2]["command"] as? String == "element_search")
        #expect(steps[2]["label"] as? String == "Done")
        #expect(steps[3]["command"] as? String == "scroll_to_edge")
        #expect(steps[3]["heistId"] as? String == "scroll-view")
        #expect(steps[3]["edge"] as? String == "bottom")
        #expect(steps[4]["command"] as? String == "dismiss_keyboard")
    }

    @Test("all registered tools route through the catalog")
    func allRegisteredToolsRouteThroughCatalog() throws {
        for tool in ToolDefinitions.all {
            let request = try routed(tool.name, minimalArguments(for: tool.name))

            #expect(request["command"] is String, "\(tool.name) did not produce a command")
        }
    }

    @Test("unknown tool returns routing error")
    func unknownToolReturnsRoutingError() {
        let result = ButtonHeistMCPServer.routeToolRequest(name: "not_a_tool", arguments: [:])

        guard case .failure(let error) = result else {
            Issue.record("Expected routing failure")
            return
        }
        #expect(error.message == "Unknown tool: not_a_tool")
    }

    private func routed(
        _ name: String,
        _ arguments: [String: Any]
    ) throws -> [String: Any] {
        switch ButtonHeistMCPServer.routeToolRequest(name: name, arguments: arguments) {
        case .success(let request):
            return request
        case .failure(let error):
            throw error
        }
    }

    private func normalizeBatchSteps(_ steps: [[String: Any]]) throws -> [[String: Any]] {
        try steps.map(normalizedBatchStep)
    }

    private func normalizedBatchStep(_ step: [String: Any]) throws -> [String: Any] {
        switch FenceOperationCatalog.normalizeBatchStep(step) {
        case .success(let request):
            return request
        case .failure(let error):
            throw error
        }
    }

    private func minimalArguments(for toolName: String) -> [String: Any] {
        switch toolName {
        case "gesture":
            return ["type": "swipe"]
        case "edit_action":
            return ["action": "copy"]
        case "run_batch":
            return ["steps": [["command": "get_session_state"]]]
        default:
            return [:]
        }
    }
}
