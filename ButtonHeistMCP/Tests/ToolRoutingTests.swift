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
        let operation = try routed(TheFence.Command.connect.rawValue, ["target": .string("demo")])

        #expect(operation.command == .connect)
        #expect(operation.arguments.argumentValues["target"] == .string("demo"))
    }

    @Test("perform routes one DSL step opaquely")
    func performRoutesOneDSLStepOpaquely() throws {
        let operation = try routed(
            TheFence.Command.perform.rawValue,
            [
                "step": .string(#"Activate(.label("Pay")).expect(.change(.screen()))"#),
            ]
        )

        #expect(operation.command == .perform)
        #expect(operation.arguments.argumentValues["step"] == .string(#"Activate(.label("Pay")).expect(.change(.screen()))"#))
    }

    @Test("granular action tools are not MCP tools")
    func granularActionToolsAreNotMCPTools() {
        for name in [
            "activate",
            "type_text",
            "wait",
            "swipe",
            "dismiss_keyboard",
            "edit_action",
            "scroll",
        ] {
            let result = routeToolRequest(name: name)
            guard case .failure(let error) = result else {
                Issue.record("Expected routing failure for \(name)")
                continue
            }
            #expect(error.message == "Unknown tool: \(name)")
        }
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

    @Test("routing errors map to canonical public failures")
    func routingErrorsMapToCanonicalPublicFailures() throws {
        let result = routeToolRequest(name: "not_a_tool")

        guard case .failure(let error) = result else {
            Issue.record("Expected routing failure")
            return
        }

        let failure = try #require(FenceResponse.failure(error).publicFailure)
        #expect(failure.code == "request.invalid")
        #expect(failure.kind == .request)
        #expect(failure.message == "Unknown tool: not_a_tool")
        #expect(failure.details.phase == .request)
        #expect(failure.details.retryable == false)
    }

    @Test("MCP routes run_heist plan source opaquely")
    func runHeistDoesNotParsePlanSource() throws {
        // The MCP adapter has no knowledge of ButtonHeist plan source parsing. The
        // `plan` string is forwarded verbatim to TheFence/ThePlans.
        let arguments = try ButtonHeistMCPServer.decodeArguments(
            [
                "plan": .string("HeistPlan { Activate(.label(\"Pay\")) }"),
            ]
        )

        #expect(arguments.argumentValues["plan"] == .string("HeistPlan { Activate(.label(\"Pay\")) }"))
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

    @Test("MCP rejects nested argument trees before HeistValue conversion")
    func mcpRejectsNestedArgumentTreeBeforeHeistValueConversion() {
        let nested = Self.nestedMCPValueOverLimit()

        do {
            _ = try ButtonHeistMCPServer.decodeArguments(["argument": nested])
            Issue.record("Expected MCP argument depth limit error")
        } catch {
            #expect(
                String(describing: error)
                    .contains("MCP arguments nesting depth exceeds \(PublicJSONInputLimits.maxNestingDepth)")
            )
        }
    }

    @Test("MCP rejects oversized argument payloads before HeistValue conversion")
    func mcpRejectsOversizedArgumentPayloadBeforeHeistValueConversion() {
        let oversizedText = String(repeating: "x", count: PublicJSONInputLimits.maxRequestBytes + 1)

        do {
            _ = try ButtonHeistMCPServer.decodeArguments(["text": .string(oversizedText)])
            Issue.record("Expected MCP argument byte limit error")
        } catch {
            #expect(
                String(describing: error)
                    .contains("MCP arguments exceeds \(PublicJSONInputLimits.maxRequestBytes) bytes")
            )
        }
    }

    @Test("MCP rejects excessive argument object keys before HeistValue conversion")
    func mcpRejectsExcessiveArgumentObjectKeysBeforeHeistValueConversion() {
        let excessiveKeys = Self.mcpObjectWithEnoughKeysToExceedLimitFromRoot()

        do {
            _ = try ButtonHeistMCPServer.decodeArguments(["argument": .object(excessiveKeys)])
            Issue.record("Expected MCP argument object key limit error")
        } catch {
            #expect(
                String(describing: error)
                    .contains("MCP arguments object key count exceeds \(PublicJSONInputLimits.maxTotalObjectKeys)")
            )
        }
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

    private static func nestedMCPValueOverLimit() -> Value {
        var value = Value.string("leaf")
        for _ in 0..<PublicJSONInputLimits.maxNestingDepth {
            value = .object(["child": value])
        }
        return value
    }

    private static func mcpObjectWithEnoughKeysToExceedLimitFromRoot() -> [String: Value] {
        var object: [String: Value] = [:]
        for index in 0..<PublicJSONInputLimits.maxTotalObjectKeys {
            object[String(index)] = .int(index)
        }
        return object
    }

}
