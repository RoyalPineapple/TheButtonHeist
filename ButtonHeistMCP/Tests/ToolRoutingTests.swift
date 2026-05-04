import Testing
@testable import ButtonHeistMCP

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
        #expect(error.message == "Missing required parameter: type")
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
        #expect(error.message.contains("Unknown scroll mode: sideways"))
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
}
