import Foundation
import TheScore

/// Failure produced while normalizing an external tool name into a Fence command.
///
/// This stays separate from `FenceError`: it describes pre-dispatch routing
/// failures before a concrete Fence command exists.
public struct FenceOperationRoutingError: Error, LocalizedError, Sendable {
    public let message: String

    public var errorDescription: String? { message }
}

/// Canonical Fence operation routed from external input with typed routed request metadata.
public struct NormalizedOperation {
    public let command: TheFence.Command
    let request: TheFence.RoutedCommandRequest

    public func stringArgument(_ key: String) -> String? { request.string(key) }

    init(
        command: TheFence.Command,
        arguments: TheFence.CommandArgumentEnvelope,
        expectationPayload: TheFence.ExpectationPayload? = nil
    ) {
        self.command = command
        request = TheFence.RoutedCommandRequest(
            arguments: arguments,
            expectationPayload: expectationPayload
        )
    }
}

/// Shared routing table for MCP tool calls and batch steps.
public enum FenceOperationCatalog {
    public static func normalizeToolCall(
        name: String,
        arguments: TheFence.CommandArgumentEnvelope
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        guard let contract = TheFence.Command.mcpToolContract(named: name) else {
            return routeCommandNamed(name, arguments: arguments)
        }

        if let selector = contract.selector {
            return routeSelectorTool(contract, selector: selector, arguments: arguments)
        }

        guard let command = contract.commands.first, contract.commands.count == 1 else {
            return .failure(FenceOperationRoutingError(message: "Unknown tool: \(name)"))
        }
        return normalizeToolOperation(command: command, arguments: arguments)
    }

    public static func normalizeBatchStep(
        _ step: TheFence.CommandArgumentObject
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        normalizeCanonicalStep(
            step,
            context: "run_batch step",
            nonExecutableLabel: "batch-executable",
            isExecutable: \.isBatchExecutable
        )
    }

    public static func normalizePlaybackStep(
        commandName: String,
        arguments _: [String: HeistValue]
    ) -> Result<TheFence.Command, FenceOperationRoutingError> {
        normalizeTypedPlaybackStep(
            commandName: commandName,
            context: "heist step"
        )
    }

    private static func normalizeCanonicalStep(
        _ step: TheFence.CommandArgumentObject,
        context: String,
        nonExecutableLabel: String,
        isExecutable: KeyPath<TheFence.Command, Bool>
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        let commandName: String
        do {
            commandName = try step.requiredSchemaString("command")
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }

        var argumentValues = step.argumentValues
        argumentValues.removeValue(forKey: "command")
        let arguments = TheFence.CommandArgumentEnvelope(
            values: argumentValues,
            fieldPrefix: step.argumentFieldPrefix
        )

        return normalizeCanonicalStep(
            commandName: commandName,
            arguments: arguments,
            context: context,
            nonExecutableLabel: nonExecutableLabel,
            isExecutable: isExecutable
        )
    }

    private static func normalizeCanonicalStep(
        commandName: String,
        arguments: TheFence.CommandArgumentEnvelope,
        context: String,
        nonExecutableLabel: String,
        isExecutable: KeyPath<TheFence.Command, Bool>
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        guard let command = TheFence.Command(rawValue: commandName) else {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command must be a canonical TheFence.Command; unknown command \"\(commandName)\""
            ))
        }

        guard command[keyPath: isExecutable] else {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command \"\(command.rawValue)\" is not \(nonExecutableLabel)"
            ))
        }

        if let error = canonicalShapeError(for: command, arguments: arguments, context: context) {
            return .failure(error)
        }

        return .success(NormalizedOperation(command: command, arguments: arguments))
    }

    private static func normalizeTypedPlaybackStep(
        commandName: String,
        context: String
    ) -> Result<TheFence.Command, FenceOperationRoutingError> {
        guard let command = TheFence.Command(rawValue: commandName) else {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command must be a canonical TheFence.Command; unknown command \"\(commandName)\""
            ))
        }

        guard command.isPlaybackExecutable else {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command \"\(command.rawValue)\" is not playback-executable"
            ))
        }

        return .success(command)
    }

    private static func routeCommandNamed(
        _ name: String,
        arguments: TheFence.CommandArgumentEnvelope
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        guard let command = TheFence.Command(rawValue: name) else {
            return .failure(FenceOperationRoutingError(message: "Unknown tool: \(name)"))
        }
        guard command.mcpExposure == .directTool else {
            if let message = groupedToolRoutingMessage(for: command) {
                return .failure(FenceOperationRoutingError(message: message))
            }
            return .failure(FenceOperationRoutingError(message: "Unknown tool: \(name)"))
        }

        return normalizeToolOperation(command: command, arguments: arguments)
    }

    private static func groupedToolRoutingMessage(for command: TheFence.Command) -> String? {
        switch command.mcpExposure {
        case .groupedUnder(let toolName):
            guard let contract = TheFence.Command.mcpToolContract(named: toolName),
                  let selector = contract.selector,
                  let selectorValue = selector.selectorValue(for: command) else {
                return nil
            }
            return groupedToolRoutingMessage(
                rawToolName: command.rawValue,
                groupedToolName: toolName,
                selectorName: selector.parameter.key,
                selectorValue: selectorValue
            )
        default:
            return nil
        }
    }

    private static func groupedToolRoutingMessage(
        rawToolName: String,
        groupedToolName: String,
        selectorName: String,
        selectorValue: String
    ) -> String {
        "Tool \"\(rawToolName)\" is grouped under \"\(groupedToolName)\"; call \(groupedToolName) with \(selectorName)=\"\(selectorValue)\"."
    }

    private static func canonicalShapeError(
        for command: TheFence.Command,
        arguments: some TheFence.CommandArgumentReadable,
        context: String
    ) -> FenceOperationRoutingError? {
        guard let contract = TheFence.Command.mcpToolContract(named: command.rawValue),
              let selector = contract.selector else {
            return nil
        }

        let selectorKey = selector.parameter.key
        guard arguments.keys.contains(selectorKey) else { return nil }

        let commandParameterKeys = Set(command.parameters.map(\.key))
        if !commandParameterKeys.contains(selectorKey) {
            return .init(
                message: "\(context) \"\(command.rawValue)\" uses the MCP \(selectorKey) selector; " +
                    "use canonical Fence commands \(rawCommandList(contract.commands))."
            )
        }

        let selectorValue: String?
        do {
            selectorValue = try arguments.schemaString(selectorKey)
        } catch let error as SchemaValidationError {
            return .init(message: error.message)
        } catch {
            return .init(message: error.localizedDescription)
        }
        guard let selectorValue,
              selector.consumesValue(selectorValue),
              let selectedCommand = selector.command(for: selectorValue),
              selectedCommand != command else {
            return nil
        }
        return .init(
            message: "\(context) \"\(command.rawValue)\" uses the MCP \(selectorValue) selector; " +
                "use canonical Fence command \(selectedCommand.rawValue)."
        )
    }

    private static func rawCommandList(_ commands: [TheFence.Command]) -> String {
        let commandNames = commands.map(\.rawValue)
        switch commandNames.count {
        case 0:
            return ""
        case 1:
            return commandNames[0]
        case 2:
            return "\(commandNames[0]) or \(commandNames[1])"
        default:
            return commandNames.dropLast().joined(separator: ", ") + ", or \(commandNames.last ?? "")"
        }
    }

    private static func routeSelectorTool(
        _ contract: MCPToolContract,
        selector: MCPToolSelector,
        arguments: TheFence.CommandArgumentEnvelope
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        let rawValue: String?
        do {
            rawValue = try selectorValue(in: arguments, selector: selector)
        } catch let error as SchemaValidationError {
            return .failure(selectorRoutingError(error, contract: contract, selector: selector))
        } catch {
            return .failure(selectorRoutingError(error.localizedDescription, contract: contract, selector: selector))
        }

        guard let command = selector.command(for: rawValue) else {
            return .failure(FenceOperationRoutingError(
                message: "Unknown \(contract.name) selector value: \(rawValue ?? "missing")"
            ))
        }
        var operationValues = arguments.argumentValues
        if selector.consumesValue(rawValue) {
            operationValues.removeValue(forKey: selector.parameter.key)
        }
        operationValues = selectorRoutedOperationValues(
            operationValues,
            contract: contract,
            command: command
        )
        let operationArguments = TheFence.CommandArgumentEnvelope(
            values: operationValues,
            fieldPrefix: arguments.argumentFieldPrefix
        )
        return normalizeToolOperation(command: command, arguments: operationArguments)
    }

    private static func selectorRoutedOperationValues(
        _ values: [String: TheFence.CommandArgumentValue],
        contract: MCPToolContract,
        command: TheFence.Command
    ) -> [String: TheFence.CommandArgumentValue] {
        guard contract.name == TheFence.Command.scroll.rawValue else { return values }
        let allowedKeys = Set(command.parameters.map(\.key))
        return values.filter { allowedKeys.contains($0.key) }
    }

    private static func normalizeToolOperation(
        command: TheFence.Command,
        arguments: TheFence.CommandArgumentEnvelope
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        let expectationPayload: TheFence.ExpectationPayload?
        let operationArguments: TheFence.CommandArgumentEnvelope
        do {
            let parsedExpectation = try parsedExpectationPayload(
                for: command,
                arguments: arguments
            )
            expectationPayload = parsedExpectation.payload
            operationArguments = parsedExpectation.arguments
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch let error as FenceError {
            return .failure(FenceOperationRoutingError(message: error.coreMessage))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }

        return .success(NormalizedOperation(
            command: command,
            arguments: operationArguments,
            expectationPayload: expectationPayload
        ))
    }

    private static func parsedExpectationPayload(
        for command: TheFence.Command,
        arguments: TheFence.CommandArgumentEnvelope
    ) throws -> (payload: TheFence.ExpectationPayload?, arguments: TheFence.CommandArgumentEnvelope) {
        guard command.acceptsExpectationPayload,
              arguments.keys.contains("expect") || arguments.keys.contains("timeout") else {
            return (nil, arguments)
        }

        let payload = try TheFence.ExpectationPayload(arguments: arguments)
        var operationValues = arguments.argumentValues
        operationValues.removeValue(forKey: "expect")
        return (payload, TheFence.CommandArgumentEnvelope(values: operationValues))
    }

    private static func selectorValue(
        in arguments: some TheFence.CommandArgumentReadable,
        selector: MCPToolSelector
    ) throws -> String? {
        let key = selector.parameter.key
        let rawValue = try arguments.schemaString(key)
        guard let enumValues = selector.parameter.enumValues else { return rawValue ?? selector.defaultValue }

        if let rawValue {
            guard enumValues.contains(rawValue) else {
                throw SchemaValidationError(
                    field: key,
                    observed: SchemaValidationError.observedDescription(rawValue),
                    expected: SchemaValidationError.expectedEnumValues(enumValues)
                )
            }
            return rawValue
        }

        guard !selector.parameter.required else {
            throw SchemaValidationError(
                field: key,
                observed: nil,
                expected: SchemaValidationError.expectedEnumValues(enumValues)
            )
        }
        return selector.defaultValue
    }

    private static func selectorRoutingError(
        _ error: SchemaValidationError,
        contract: MCPToolContract,
        selector: MCPToolSelector
    ) -> FenceOperationRoutingError {
        selectorRoutingError(error.message, contract: contract, selector: selector)
    }

    private static func selectorRoutingError(
        _ message: String,
        contract: MCPToolContract,
        selector: MCPToolSelector
    ) -> FenceOperationRoutingError {
        FenceOperationRoutingError(
            message: "\(contract.name).\(selector.parameter.key): \(message)"
        )
    }
}

private extension TheFence.Command {
    var acceptsExpectationPayload: Bool {
        parameters.contains { $0.key == FenceParameterKey.expect.rawValue }
    }
}
