import Foundation
import MCP
import Testing
@testable import ButtonHeistMCP
import ButtonHeist
import ThePlans

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

    @Test("run_heist source_file compiles before Fence routing")
    func runHeistSourceFileCompilesBeforeFenceRouting() throws {
        let temp = try TemporaryMCPDirectory()
        let sourceURL = temp.url.appendingPathComponent("LoginFlow.swift")
        try "".write(to: sourceURL, atomically: true, encoding: .utf8)

        let arguments = try ButtonHeistMCPServer.decodeArguments(
            [
                "source_file": .string(sourceURL.path),
                "entry": .string("makeHeist"),
            ],
            forTool: TheFence.Command.runHeist.rawValue,
            compileSwiftFile: { _, _ in
                HeistPlan(body: [.warn(WarnStep(message: "from MCP"))])
            }
        )

        #expect(arguments.argumentValues["source_file"] == nil)
        #expect(arguments.argumentValues["entry"] == nil)
        #expect(arguments.argumentValues["version"] == .int(2))
        guard case .array(let body)? = arguments.argumentValues["body"] else {
            Issue.record("Expected compiled heist body")
            return
        }
        #expect(body.count == 1)
    }

    @Test("run_heist malformed source reports adapter error")
    func runHeistMalformedSourceReportsAdapterError() throws {
        let temp = try TemporaryMCPDirectory()
        let sourceURL = temp.url.appendingPathComponent("Broken.swift")
        try "".write(to: sourceURL, atomically: true, encoding: .utf8)

        do {
            _ = try ButtonHeistMCPServer.decodeArguments(
                [
                    "source_file": .string(sourceURL.path),
                    "entry": .string("makeHeist"),
                ],
                forTool: TheFence.Command.runHeist.rawValue,
                compileSwiftFile: { source, _ in
                    throw HeistSourceCompilerError.compileFailed(source.path, "expected declaration")
                }
            )
            Issue.record("Expected adapter compile error")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("failed to compile Swift heist source"))
            #expect(!message.contains("SchemaValidationError"))
        }
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

private final class TemporaryMCPDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("buttonheist-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
