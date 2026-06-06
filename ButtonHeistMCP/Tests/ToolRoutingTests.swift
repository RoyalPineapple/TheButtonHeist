import Foundation
import MCP
import Testing
@testable import ButtonHeistMCP
import ButtonHeist

struct ToolRoutingTests {
    private typealias Argument = HeistValue
    private typealias RoutedCommand = (command: TheFence.Command, arguments: TheFence.CommandArgumentEnvelope)

    @Test("direct tools route to same command")
    func directToolRoutesToSameCommand() throws {
        let operation = try routed(TheFence.Command.startHeist.rawValue, ["identifier": .string("demo")])

        #expect(operation.command == .startHeist)
        #expect(operation.arguments.argumentValues["identifier"] == .string("demo"))
    }

    @Test("canonical gesture tools route directly")
    func canonicalGestureToolsRouteDirectly() throws {
        let operation = try routed(
            TheFence.Command.swipe.rawValue,
            [
                "target": .object(["heistId": .string("element-1")]),
                "direction": .string("left"),
            ]
        )

        #expect(operation.command == .swipe)
        #expect(operation.arguments.argumentValues["heistId"] == nil)
        #expect(operation.arguments.argumentValues["direction"] == .string("left"))
    }

    @Test("dismiss_keyboard routes directly")
    func dismissKeyboardRoutesDirectly() throws {
        let operation = try routed(TheFence.Command.dismissKeyboard.rawValue, [:])

        #expect(operation.command == .dismissKeyboard)
    }

    @Test("edit_action keeps standard edit actions")
    func editActionKeepsStandardEditActions() throws {
        let operation = try routed(TheFence.Command.editAction.rawValue, ["action": .string("copy")])

        #expect(operation.command == .editAction)
        #expect(operation.arguments.argumentValues["action"] == .string("copy"))
    }

    @Test("unknown tool returns routing error")
    func unknownToolReturnsRoutingError() {
        let result = routeToolRequest(name: "not_a_tool")

        guard case .failure(let error) = result else {
            Issue.record("Expected routing failure")
            return
        }
        #expect(error.message == "Unknown tool: not_a_tool")
    }

    @Test("MCP routes run_heist plan source opaquely")
    func runHeistDoesNotParsePlanSource() throws {
        // The MCP adapter has no knowledge of ButtonHeist plan source parsing. The
        // `plan` string is forwarded verbatim to TheFence/ThePlans.
        let arguments = try ButtonHeistMCPServer.decodeArguments(
            [
                "plan": .string("Activate(.label(\"Pay\"))"),
            ]
        )

        #expect(arguments.argumentValues["plan"] == .string("Activate(.label(\"Pay\"))"))
    }

    @Test("run_heist tool schema exposes plan source")
    func runHeistToolSchemaHasPlanSource() throws {
        guard let runHeist = ToolDefinitions.all.first(where: { $0.name == TheFence.Command.runHeist.rawValue }) else {
            Issue.record("run_heist tool not found")
            return
        }
        let schema = String(describing: runHeist.inputSchema)
        #expect(schema.contains("plan"))
    }

    @Test("run_heist routes root argument opaquely")
    func runHeistRoutesRootArgument() throws {
        let operation = try routed(
            TheFence.Command.runHeist.rawValue,
            [
                "path": .string("Search.heist"),
                "argument": .object([
                    "type": .string("string"),
                    "value": .string("milk"),
                ]),
            ]
        )

        #expect(operation.command == .runHeist)
        #expect(operation.arguments.argumentValues["argument"] == .object([
            "type": .string("string"),
            "value": .string("milk"),
        ]))
    }

    @Test("heist discovery tools route directly with detail and selector arguments")
    func heistDiscoveryToolsRouteDirectly() throws {
        let list = try routed(
            TheFence.Command.listHeists.rawValue,
            [
                "detail": .string("detailed"),
                "path": .string("Flow.heist"),
            ]
        )
        let describe = try routed(
            TheFence.Command.describeHeist.rawValue,
            [
                "heist": .string("Cart.checkout"),
                "path": .string("Flow.heist"),
            ]
        )

        #expect(list.command == .listHeists)
        #expect(list.arguments.argumentValues["detail"] == .string("detailed"))
        #expect(list.arguments.argumentValues["path"] == .string("Flow.heist"))
        #expect(describe.command == .describeHeist)
        #expect(describe.arguments.argumentValues["heist"] == .string("Cart.checkout"))
        #expect(describe.arguments.argumentValues["path"] == .string("Flow.heist"))
    }

    private func routeToolRequest(
        name: String
    ) -> Result<TheFence.Command, FenceOperationRoutingError> {
        TheFence.Command.routeToolCall(named: name)
    }

    private func routed(
        _ name: String,
        _ arguments: [String: Argument]
    ) throws -> RoutedCommand {
        switch routeToolRequest(name: name) {
        case .success(let command):
            return (command: command, arguments: envelope(arguments))
        case .failure(let error):
            throw error
        }
    }

    private func envelope(_ arguments: [String: Argument] = [:]) -> TheFence.CommandArgumentEnvelope {
        TheFence.CommandArgumentEnvelope(values: arguments)
    }

}
