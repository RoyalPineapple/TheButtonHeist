import Foundation
import MCP
import Testing
@testable import ButtonHeistMCP
@_spi(ButtonHeistTooling) import ButtonHeist

struct ToolRoutingTests {
    private typealias Argument = Value
    private typealias RoutedCommand = FenceCommandInput

    @Test("direct tools route to same command")
    func directToolRoutesToSameCommand() throws {
        let operation = try routed(TheFence.Command.connect.rawValue, ["target": .string("demo")])

        #expect(operation.command == .connect)
        #expect(operation.arguments.value(for: .target) == .string("demo"))
    }

    @Test("tool routing exposure matches descriptors")
    func toolRoutingExposureMatchesDescriptors() throws {
        for descriptor in TheFence.Command.descriptors {
            let request = try MCPToolRequest(name: descriptor.command.rawValue, arguments: [:])
            let result = ButtonHeistMCPServer.routedToolRequest(request)

            switch (descriptor.mcpExposure, result) {
            case (.directTool, .success(let input)):
                #expect(input.command == descriptor.command)
            case (.notExposed, .failure(let error)):
                #expect(error.message == "Unknown tool: \(descriptor.command.rawValue)")
            case (.directTool, .failure(let error)):
                Issue.record("Expected \(descriptor.command.rawValue) to route, got \(error.message)")
            case (.notExposed, .success):
                Issue.record("Expected \(descriptor.command.rawValue) to be hidden from MCP routing")
            }
        }
    }

    @Test("perform routes one DSL step opaquely")
    func performRoutesOneDSLStepOpaquely() throws {
        let operation = try routed(
            TheFence.Command.perform.rawValue,
            [
                "step": .string(#"Activate(.label("Pay")).expect(.changed(.screen()))"#),
            ]
        )

        #expect(operation.command == .perform)
        #expect(operation.arguments.value(for: .step) == .string(#"Activate(.label("Pay")).expect(.changed(.screen()))"#))
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

        let failure = try #require(FenceResponse.failure(error).diagnosticFailure)
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
        let operation = try routed(
            TheFence.Command.runHeist.rawValue,
            [
                "plan": .string("HeistPlan { Activate(.label(\"Pay\")) }"),
            ]
        )

        #expect(operation.command == .runHeist)
        #expect(operation.arguments.value(for: .plan) == .string("HeistPlan { Activate(.label(\"Pay\")) }"))
    }

    @Test("run_heist tool schema exposes plan source")
    func runHeistToolSchemaHasPlanSource() throws {
        guard let runHeist = ToolDefinitions.all.first(where: { $0.name == TheFence.Command.runHeist.rawValue }) else {
            Issue.record("run_heist tool not found")
            return
        }
        #expect(schemaValue(at: ["properties", "plan"], in: runHeist.inputSchema) != nil)
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
        #expect(operation.arguments.value(for: .argument) == .object([
            "type": .string("string"),
            "value": .string("milk"),
        ]))
    }

    @Test("MCP rejects nested argument trees before HeistValue conversion")
    func mcpRejectsNestedArgumentTreeBeforeHeistValueConversion() {
        let nested = Self.nestedMCPValueOverLimit()

        do {
            _ = try MCPToolRequest(name: "not_a_tool", arguments: ["argument": nested])
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
            _ = try MCPToolRequest(name: "not_a_tool", arguments: ["text": .string(oversizedText)])
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
            _ = try MCPToolRequest(name: "not_a_tool", arguments: ["argument": .object(excessiveKeys)])
            Issue.record("Expected MCP argument object key limit error")
        } catch {
            #expect(
                String(describing: error)
                    .contains("MCP arguments object key count exceeds \(PublicJSONInputLimits.maxTotalObjectKeys)")
            )
        }
    }

    @Test func `MCP tool request rejects null before routing`() {
        do {
            _ = try MCPToolRequest(
                name: "not_a_tool",
                arguments: ["argument": .null]
            )
            Issue.record("Expected MCP argument null rejection")
        } catch {
            #expect(String(describing: error).contains("MCP arguments contains null"))
        }
    }

    @Test func `MCP tool request routes after typed argument boundary`() throws {
        let request = try MCPToolRequest(
            name: "not_a_tool",
            arguments: ["argument": .string("accepted")]
        )

        let result = ButtonHeistMCPServer.routedToolRequest(request)

        guard case .failure(let error) = result else {
            Issue.record("Expected routing failure after argument boundary")
            return
        }
        #expect(error.message == "Unknown tool: not_a_tool")
    }

    @Test func `MCP tool arguments reject binary data before command envelopes`() {
        do {
            _ = try MCPToolRequest(
                name: "not_a_tool",
                arguments: ["attachment": .data(mimeType: "application/octet-stream", Data([0]))]
            )
            Issue.record("Expected MCP argument binary data rejection")
        } catch {
            #expect(String(describing: error).contains("MCP arguments contains binary data"))
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
        #expect(list.arguments.value(for: .detail) == .string("detailed"))
        #expect(list.arguments.value(for: .path) == .string("Flow.heist"))
        #expect(describe.command == .describeHeist)
        #expect(describe.arguments.value(for: .heist) == .string("Cart.checkout"))
        #expect(describe.arguments.value(for: .path) == .string("Flow.heist"))
    }

    @Test("core router accepts a prebuilt command argument envelope")
    func coreRouterAcceptsPrebuiltCommandArgumentEnvelope() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: ["target": .string("demo")])

        let result = TheFence.Command.routeToolRequest(
            named: TheFence.Command.connect.rawValue,
            arguments: envelope
        )

        guard case .success(let operation) = result else {
            Issue.record("Expected core routing success")
            return
        }
        #expect(operation.command == .connect)
        #expect(operation.arguments.value(for: .target) == .string("demo"))
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
        let request = try MCPToolRequest(name: name, arguments: arguments)
        switch ButtonHeistMCPServer.routedToolRequest(request) {
        case .success(let request):
            return request
        case .failure(let error):
            throw error
        }
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

private func schemaValue(at path: [String], in root: Value) -> Value? {
    path.reduce(Optional(root)) { value, key in
        value?.objectValue?[key]
    }
}
