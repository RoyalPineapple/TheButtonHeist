import Foundation
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

    @Test("run_batch still accepts canonical Fence command shapes")
    func runBatchAcceptsCanonicalFenceCommandShapes() throws {
        let steps = try normalizeBatchSteps([
            [
                "command": .string(TheFence.Command.swipe.rawValue),
                "target": .object(["heistId": .string("element-1")]),
                "direction": .string("right"),
            ],
            [
                "command": .string(TheFence.Command.scrollToVisible.rawValue),
                "target": .object(["heistId": .string("element-1")]),
            ],
            ["command": .string(TheFence.Command.dismissKeyboard.rawValue)],
        ])

        #expect(steps[0].command == .swipe)
        #expect(steps[0].arguments.argumentValues["heistId"] == nil)
        #expect(steps[0].arguments.argumentValues["direction"] == .string("right"))
        #expect(steps[1].command == .scrollToVisible)
        #expect(steps[1].arguments.argumentValues["heistId"] == nil)
        #expect(steps[2].command == .dismissKeyboard)
    }

    @Test("run_batch rejects non-canonical command objects")
    func runBatchRejectsNonCanonicalCommandObjects() {
        let cases: [(step: [String: Argument], message: String)] = [
            (["command": .string("not_a_command")],
             "run_batch step command must be a canonical TheFence.Command; unknown command \"not_a_command\""),
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

    @Test("run_batch rejects explicit non-batch commands")
    func runBatchRejectsExplicitNonBatchCommands() {
        let result = normalizeBatchStepResult(["command": .string(TheFence.Command.getScreen.rawValue)])
        guard case .failure(let error) = result else {
            Issue.record("Expected routing failure")
            return
        }
        #expect(error.message.contains("run_batch step command \"get_screen\" is not supported"))
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

    private func routeToolRequest(
        name: String
    ) -> Result<TheFence.Command, FenceOperationRoutingError> {
        FenceOperationCatalog.normalizeToolCall(name: name)
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

    private func normalizeBatchSteps(_ steps: [[String: Argument]]) throws -> [RoutedCommand] {
        try steps.map(normalizedBatchStep)
    }

    private func normalizedBatchStep(_ step: [String: Argument]) throws -> RoutedCommand {
        switch normalizeBatchStepResult(step) {
        case .success(let routed):
            return routed
        case .failure(let error):
            throw error
        }
    }

    private func normalizeBatchStepResult(
        _ step: [String: Argument]
    ) -> Result<RoutedCommand, FenceOperationRoutingError> {
        FenceOperationCatalog.normalizeBatchStep(TheFence.CommandArgumentEnvelope(values: step, fieldPrefix: nil))
    }

    private func envelope(_ arguments: [String: Argument] = [:]) -> TheFence.CommandArgumentEnvelope {
        TheFence.CommandArgumentEnvelope(values: arguments)
    }

}
