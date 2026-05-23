import Foundation
import Testing
@testable import ButtonHeistMCP
import ButtonHeist

struct ToolRoutingTests {

    @Test("direct tools route to same command")
    func directToolRoutesToSameCommand() throws {
        let operation = try routed(TheFence.Command.startHeist.rawValue, ["identifier": "demo"])

        #expect(operation.command == .startHeist)
        #expect(operation.stringArgument("identifier") == "demo")
    }

    @Test("gesture type routes to command and removes type")
    func gestureTypeRoutesToCommand() throws {
        let operation = try routed(TheFence.Command.gestureMCPToolName, ["type": TheFence.Command.swipe.rawValue, "direction": "left"])

        #expect(operation.command == .swipe)
        #expect(operation.stringArgument("type") == nil)
        #expect(operation.stringArgument("direction") == "left")
    }

    @Test("gesture requires type")
    func gestureRequiresType() {
        let result = ButtonHeistMCPServer.routeToolRequest(name: TheFence.Command.gestureMCPToolName, arguments: [:])

        guard case .failure(let error) = result else {
            Issue.record("Expected routing failure")
            return
        }
        let gestureSelector = TheFence.Command.mcpToolContract(named: TheFence.Command.gestureMCPToolName)!.selector!
        #expect(
            error.message == "schema validation failed for \(gestureSelector.parameter.key): observed missing; " +
                "expected \(SchemaValidationError.expectedEnumValues(gestureSelector.parameter.enumValues!))"
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
            let operation = try routed(TheFence.Command.scroll.rawValue, arguments)

            #expect(operation.command.rawValue == routeCase.command)
            #expect(operation.stringArgument("mode") == nil)
            #expect(operation.stringArgument("direction") == "down")
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
        let scrollSelector = TheFence.Command.mcpToolContract(named: TheFence.Command.scroll.rawValue)!.selector!
        #expect(
            error.message == "schema validation failed for \(scrollSelector.parameter.key): " +
                "observed string \"sideways\"; " +
                "expected \(SchemaValidationError.expectedEnumValues(scrollSelector.parameter.enumValues!))"
        )
    }

    @Test("edit_action dismiss routes to dismiss_keyboard")
    func editActionDismissRoutesToDismissKeyboard() throws {
        let operation = try routed(TheFence.Command.editAction.rawValue, ["action": "dismiss"])

        #expect(operation.command == .dismissKeyboard)
        #expect(operation.stringArgument("action") == nil)
    }

    @Test("edit_action keeps standard edit actions")
    func editActionKeepsStandardEditActions() throws {
        let operation = try routed(TheFence.Command.editAction.rawValue, ["action": "copy"])

        #expect(operation.command == .editAction)
        #expect(operation.stringArgument("action") == "copy")
    }

    @Test("run_batch still accepts canonical Fence command shapes")
    func runBatchAcceptsCanonicalFenceCommandShapes() throws {
        let steps = try normalizeBatchSteps([
            ["command": TheFence.Command.swipe.rawValue, "direction": "right"],
            ["command": TheFence.Command.scrollToVisible.rawValue, "heistId": "element-1"],
            ["command": TheFence.Command.dismissKeyboard.rawValue],
        ])

        #expect(steps[0].command == .swipe)
        #expect(steps[0].stringArgument("direction") == "right")
        #expect(steps[1].command == .scrollToVisible)
        #expect(steps[1].stringArgument("heistId") == "element-1")
        #expect(steps[2].command == .dismissKeyboard)
    }

    @Test("run_batch rejects grouped MCP tool shapes")
    func runBatchRejectsGroupedMCPToolShapes() {
        let scrollContract = TheFence.Command.mcpToolContract(named: TheFence.Command.scroll.rawValue)!
        let scrollSelector = scrollContract.selector!
        let editActionContract = TheFence.Command.mcpToolContract(named: TheFence.Command.editAction.rawValue)!
        let editActionSelector = editActionContract.selector!
        let dismissSelectorValue = editActionSelector.consumedValues
            .first(where: { editActionSelector.command(for: $0) == .dismissKeyboard })!
        let dismissCommand = editActionSelector.command(for: dismissSelectorValue)!

        let cases: [(step: [String: Any], message: String)] = [
            (
                [
                    "command": TheFence.Command.gestureMCPToolName,
                    "type": TheFence.Command.swipe.rawValue,
                    "direction": "left",
                ],
                "run_batch step command must be a canonical TheFence.Command; " +
                    "unknown command \"\(TheFence.Command.gestureMCPToolName)\""
            ),
            (
                [
                    "command": TheFence.Command.scroll.rawValue,
                    "mode": ScrollMode.search.rawValue,
                    "label": "Done",
                ],
                "run_batch step \"\(TheFence.Command.scroll.rawValue)\" uses the MCP " +
                    "\(scrollSelector.parameter.key) selector; use canonical Fence commands " +
                    "\(rawCommandList(scrollContract.commands))."
            ),
            (
                ["command": TheFence.Command.editAction.rawValue, "action": dismissSelectorValue],
                "run_batch step \"\(TheFence.Command.editAction.rawValue)\" uses the MCP " +
                    "\(dismissSelectorValue) selector; use canonical Fence command \(dismissCommand.rawValue)."
            ),
        ]

        for testCase in cases {
            let result = normalizeBatchStepResult(testCase.step)
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
            let result = normalizeBatchStepResult(["command": command.rawValue])
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
                "Tool \"\(TheFence.Command.swipe.rawValue)\" is grouped under " +
                    "\"\(TheFence.Command.gestureMCPToolName)\"; " +
                    "call \(TheFence.Command.gestureMCPToolName) with type=\"\(TheFence.Command.swipe.rawValue)\"."
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
        #expect(steps[0].stringArgument("direction") == "up")
        #expect(steps[1].command == .scrollToVisible)
        #expect(steps[1].stringArgument("heistId") == "element-1")
        #expect(steps[2].command == .elementSearch)
        #expect(steps[2].stringArgument("label") == "Done")
        #expect(steps[3].command == .scrollToEdge)
        #expect(steps[3].stringArgument("heistId") == "scroll-view")
        #expect(steps[3].stringArgument("edge") == "bottom")
        #expect(steps[4].command == .dismissKeyboard)
    }

    @Test("all registered tools route through the catalog")
    func allRegisteredToolsRouteThroughCatalog() throws {
        for tool in ToolDefinitions.all {
            let operation = try routed(tool.name, minimalArguments(for: tool.name))

            #expect(!operation.command.rawValue.isEmpty, "\(tool.name) did not produce a command")
        }
    }

    @Test("selector-backed MCP tools route every selector value through command contracts")
    func selectorBackedToolsRouteEverySelectorValueThroughCommandContracts() throws {
        for contract in TheFence.Command.mcpToolContracts {
            guard let selector = contract.selector else { continue }
            for selectorValue in selector.parameter.enumValues ?? [] {
                let operation = try routed(contract.name, [selector.parameter.key: selectorValue])
                let expectedCommand = try #require(selector.command(for: selectorValue))

                #expect(operation.command == expectedCommand)
                if selector.consumesValue(selectorValue) {
                    #expect(operation.stringArgument(selector.parameter.key) == nil)
                } else {
                    #expect(operation.stringArgument(selector.parameter.key) == selectorValue)
                }
            }
        }
    }

    @Test("server tool routing delegates to shared Fence catalog")
    func serverToolRoutingDelegatesToSharedFenceCatalog() throws {
        for tool in ToolDefinitions.all {
            let arguments = minimalArguments(for: tool.name)
            let serverResult = ButtonHeistMCPServer.routeToolRequest(name: tool.name, arguments: arguments)
            let catalogResult = FenceOperationCatalog.normalizeToolCall(name: tool.name, arguments: arguments)

            switch (serverResult, catalogResult) {
            case (.success(let serverOperation), .success(let catalogOperation)):
                #expect(serverOperation.command == catalogOperation.command)

            case (.failure(let serverError), .failure(let catalogError)):
                #expect(serverError.message == catalogError.message)

            case (.success, .failure), (.failure, .success):
                Issue.record("\(tool.name) server routing diverged from FenceOperationCatalog")
            }
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
    ) throws -> NormalizedOperation {
        switch ButtonHeistMCPServer.routeToolRequest(name: name, arguments: arguments) {
        case .success(let operation):
            return operation
        case .failure(let error):
            throw error
        }
    }

    private func normalizeBatchSteps(_ steps: [[String: Any]]) throws -> [NormalizedOperation] {
        try steps.map(normalizedBatchStep)
    }

    private func normalizedBatchStep(_ step: [String: Any]) throws -> NormalizedOperation {
        switch normalizeBatchStepResult(step) {
        case .success(let operation):
            return operation
        case .failure(let error):
            throw error
        }
    }

    private func normalizeBatchStepResult(
        _ step: [String: Any]
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        FenceOperationCatalog.normalizeBatchStep(step)
    }

    private func minimalArguments(for toolName: String) -> [String: Any] {
        switch toolName {
        case TheFence.Command.gestureMCPToolName:
            return ["type": TheFence.Command.swipe.rawValue]
        case TheFence.Command.editAction.rawValue:
            return ["action": "copy"]
        case TheFence.Command.runBatch.rawValue:
            return ["steps": [["command": TheFence.Command.getSessionState.rawValue]]]
        default:
            return [:]
        }
    }

    /// Mirrors the formatting logic in `FenceOperationCatalog.rawCommandList` for test assertions.
    private func rawCommandList(_ commands: [TheFence.Command]) -> String {
        let names = commands.map(\.rawValue)
        switch names.count {
        case 0:
            return ""
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) or \(names[1])"
        default:
            return names.dropLast().joined(separator: ", ") + ", or \(names.last!)"
        }
    }
}
