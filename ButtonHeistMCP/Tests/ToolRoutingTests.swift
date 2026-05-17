import Testing
@testable import ButtonHeistMCP
import ButtonHeist

struct ToolRoutingTests {

    @Test("direct tools route to same command")
    func directToolRoutesToSameCommand() throws {
        let request = try routed(TheFence.Command.startHeist.rawValue, ["identifier": "demo"])

        #expect(request["command"] as? String == TheFence.Command.startHeist.rawValue)
        #expect(request["identifier"] as? String == "demo")
    }

    @Test("gesture type routes to command and removes type")
    func gestureTypeRoutesToCommand() throws {
        let request = try routed("gesture", ["type": TheFence.Command.swipe.rawValue, "direction": "left"])

        #expect(request["command"] as? String == TheFence.Command.swipe.rawValue)
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
        #expect(
            error.message == "schema validation failed for type: observed missing; " +
                "expected enum one of one_finger_tap, long_press, swipe, drag, " +
                "pinch, rotate, two_finger_tap, draw_path, draw_bezier"
        )
    }

    @Test("scroll modes route to concrete commands")
    func scrollModesRouteToConcreteCommands() throws {
        let cases: [(mode: String?, command: String)] = [
            (nil, TheFence.Command.scroll.rawValue),
            (ScrollMode.page.rawValue, TheFence.Command.scroll.rawValue),
            (ScrollMode.toVisible.rawValue, TheFence.Command.scrollToVisible.rawValue),
            (ScrollMode.search.rawValue, TheFence.Command.elementSearch.rawValue),
            (ScrollMode.toEdge.rawValue, TheFence.Command.scrollToEdge.rawValue),
        ]

        for routeCase in cases {
            var arguments: [String: Any] = ["direction": "down"]
            if let mode = routeCase.mode {
                arguments["mode"] = mode
            }
            let request = try routed(TheFence.Command.scroll.rawValue, arguments)

            #expect(request["command"] as? String == routeCase.command)
            #expect(request["mode"] == nil)
            #expect(request["direction"] as? String == "down")
        }
    }

    @Test("scroll rejects unknown mode")
    func scrollRejectsUnknownMode() {
        let result = ButtonHeistMCPServer.routeToolRequest(
            name: TheFence.Command.scroll.rawValue,
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
        let request = try routed(TheFence.Command.editAction.rawValue, ["action": "dismiss"])

        #expect(request["command"] as? String == TheFence.Command.dismissKeyboard.rawValue)
        #expect(request["action"] == nil)
    }

    @Test("edit_action keeps standard edit actions")
    func editActionKeepsStandardEditActions() throws {
        let request = try routed(TheFence.Command.editAction.rawValue, ["action": "copy"])

        #expect(request["command"] as? String == TheFence.Command.editAction.rawValue)
        #expect(request["action"] as? String == "copy")
    }

    @Test("run_batch still accepts canonical Fence command shapes")
    func runBatchAcceptsCanonicalFenceCommandShapes() throws {
        let steps = try normalizeBatchSteps([
            ["command": TheFence.Command.swipe.rawValue, "direction": "right"],
            ["command": TheFence.Command.scrollToVisible.rawValue, "heistId": "element-1"],
            ["command": TheFence.Command.dismissKeyboard.rawValue],
        ])

        #expect(steps[0].command == .swipe)
        #expect(steps[0].requestDictionary["command"] as? String == TheFence.Command.swipe.rawValue)
        #expect(steps[0].arguments["direction"] as? String == "right")
        #expect(steps[1].command == .scrollToVisible)
        #expect(steps[1].requestDictionary["command"] as? String == TheFence.Command.scrollToVisible.rawValue)
        #expect(steps[1].arguments["heistId"] as? String == "element-1")
        #expect(steps[2].command == .dismissKeyboard)
        #expect(steps[2].requestDictionary["command"] as? String == TheFence.Command.dismissKeyboard.rawValue)
    }

    @Test("run_batch rejects grouped MCP tool shapes")
    func runBatchRejectsGroupedMCPToolShapes() {
        let cases: [(step: [String: Any], message: String)] = [
            (
                ["command": "gesture", "type": TheFence.Command.swipe.rawValue, "direction": "left"],
                "run_batch step command must be a canonical TheFence.Command; unknown command \"gesture\""
            ),
            (
                [
                    "command": TheFence.Command.scroll.rawValue,
                    "mode": ScrollMode.search.rawValue,
                    "label": "Done",
                ],
                "run_batch step \"scroll\" uses the MCP mode selector; use canonical Fence commands scroll, scroll_to_visible, element_search, or scroll_to_edge."
            ),
            (
                ["command": TheFence.Command.editAction.rawValue, "action": "dismiss"],
                "run_batch step \"edit_action\" uses the MCP dismiss selector; use canonical Fence command dismiss_keyboard."
            ),
        ]

        for testCase in cases {
            let result = FenceOperationCatalog.normalizeBatchStep(testCase.step)
            guard case .failure(let error) = result else {
                Issue.record("Expected routing failure")
                continue
            }
            #expect(error.message == testCase.message)
        }
    }

    @Test("run_batch rejects non-batch-executable commands")
    func runBatchRejectsNonBatchExecutableCommands() {
        for command in [TheFence.Command.help, .status, .quit, .exit, .runBatch] {
            let result = FenceOperationCatalog.normalizeBatchStep(["command": command.rawValue])
            guard case .failure(let error) = result else {
                Issue.record("Expected routing failure for \(command.rawValue)")
                continue
            }
            #expect(error.message == "run_batch step command \"\(command.rawValue)\" is not batch-executable")
        }
    }

    @Test("top-level raw grouped commands report canonical grouped tool shape")
    func topLevelRawGroupedCommandsReportCanonicalGroupedToolShape() {
        let cases: [(toolName: String, message: String)] = [
            (
                TheFence.Command.swipe.rawValue,
                "Tool \"\(TheFence.Command.swipe.rawValue)\" is grouped under \"gesture\"; " +
                    "call gesture with type=\"\(TheFence.Command.swipe.rawValue)\"."
            ),
            (
                TheFence.Command.scrollToVisible.rawValue,
                "Tool \"\(TheFence.Command.scrollToVisible.rawValue)\" is grouped under " +
                    "\"\(TheFence.Command.scroll.rawValue)\"; call \(TheFence.Command.scroll.rawValue) " +
                    "with mode=\"\(ScrollMode.toVisible.rawValue)\"."
            ),
            (
                TheFence.Command.elementSearch.rawValue,
                "Tool \"\(TheFence.Command.elementSearch.rawValue)\" is grouped under " +
                    "\"\(TheFence.Command.scroll.rawValue)\"; call \(TheFence.Command.scroll.rawValue) " +
                    "with mode=\"\(ScrollMode.search.rawValue)\"."
            ),
            (
                TheFence.Command.scrollToEdge.rawValue,
                "Tool \"\(TheFence.Command.scrollToEdge.rawValue)\" is grouped under " +
                    "\"\(TheFence.Command.scroll.rawValue)\"; call \(TheFence.Command.scroll.rawValue) " +
                    "with mode=\"\(ScrollMode.toEdge.rawValue)\"."
            ),
            (
                TheFence.Command.dismissKeyboard.rawValue,
                "Tool \"\(TheFence.Command.dismissKeyboard.rawValue)\" is grouped under " +
                    "\"\(TheFence.Command.editAction.rawValue)\"; " +
                    "call \(TheFence.Command.editAction.rawValue) with action=\"dismiss\"."
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
            ["command": TheFence.Command.swipe.rawValue, "direction": "up"],
            ["command": TheFence.Command.scrollToVisible.rawValue, "heistId": "element-1"],
            ["command": TheFence.Command.elementSearch.rawValue, "label": "Done"],
            ["command": TheFence.Command.scrollToEdge.rawValue, "heistId": "scroll-view", "edge": "bottom"],
            ["command": TheFence.Command.dismissKeyboard.rawValue],
        ])

        #expect(steps[0].command == .swipe)
        #expect(steps[0].requestDictionary["command"] as? String == TheFence.Command.swipe.rawValue)
        #expect(steps[0].arguments["direction"] as? String == "up")
        #expect(steps[1].command == .scrollToVisible)
        #expect(steps[1].requestDictionary["command"] as? String == TheFence.Command.scrollToVisible.rawValue)
        #expect(steps[1].arguments["heistId"] as? String == "element-1")
        #expect(steps[2].command == .elementSearch)
        #expect(steps[2].requestDictionary["command"] as? String == TheFence.Command.elementSearch.rawValue)
        #expect(steps[2].arguments["label"] as? String == "Done")
        #expect(steps[3].command == .scrollToEdge)
        #expect(steps[3].requestDictionary["command"] as? String == TheFence.Command.scrollToEdge.rawValue)
        #expect(steps[3].arguments["heistId"] as? String == "scroll-view")
        #expect(steps[3].arguments["edge"] as? String == "bottom")
        #expect(steps[4].command == .dismissKeyboard)
        #expect(steps[4].requestDictionary["command"] as? String == TheFence.Command.dismissKeyboard.rawValue)
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

    private func normalizeBatchSteps(_ steps: [[String: Any]]) throws -> [NormalizedOperation] {
        try steps.map(normalizedBatchStep)
    }

    private func normalizedBatchStep(_ step: [String: Any]) throws -> NormalizedOperation {
        switch FenceOperationCatalog.normalizeBatchStep(step) {
        case .success(let operation):
            return operation
        case .failure(let error):
            throw error
        }
    }

    private func minimalArguments(for toolName: String) -> [String: Any] {
        switch toolName {
        case "gesture":
            return ["type": TheFence.Command.swipe.rawValue]
        case TheFence.Command.editAction.rawValue:
            return ["action": "copy"]
        case TheFence.Command.runBatch.rawValue:
            return ["steps": [["command": TheFence.Command.getSessionState.rawValue]]]
        default:
            return [:]
        }
    }
}
