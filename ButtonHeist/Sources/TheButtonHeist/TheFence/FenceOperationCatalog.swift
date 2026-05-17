import Foundation

/// Failure produced while normalizing an external tool name into a Fence command.
///
/// This stays separate from `FenceError`: it describes pre-dispatch routing
/// failures before a concrete Fence command exists.
public struct FenceOperationRoutingError: Error, LocalizedError, Sendable {
    public let message: String

    public var errorDescription: String? { message }
}

/// A command plus its already-normalized arguments.
///
/// External string command names are parsed into `TheFence.Command` at the
/// routing edge. The dictionary form is only reconstructed when a caller needs
/// the existing `execute(request:)` shape.
public struct NormalizedOperation {
    public let command: TheFence.Command
    public let arguments: [String: Any]

    public init(command: TheFence.Command, arguments: [String: Any]) {
        var sanitizedArguments = arguments
        sanitizedArguments.removeValue(forKey: "command")
        self.command = command
        self.arguments = sanitizedArguments
    }

    public var requestDictionary: [String: Any] {
        var request = arguments
        request["command"] = command.rawValue
        return request
    }
}

/// Shared routing table for MCP tool calls and batch steps.
public enum FenceOperationCatalog {
    public static func normalizeToolCall(
        name: String,
        arguments: [String: Any]
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
        return .success(NormalizedOperation(command: command, arguments: arguments))
    }

    public static func normalizeBatchStep(
        _ step: [String: Any]
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        let commandName: String
        do {
            commandName = try step.requiredSchemaString("command")
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }

        var arguments = step
        arguments.removeValue(forKey: "command")

        guard let command = TheFence.Command(rawValue: commandName) else {
            return .failure(FenceOperationRoutingError(
                message: "run_batch step command must be a canonical TheFence.Command; unknown command \"\(commandName)\""
            ))
        }

        guard command.isBatchExecutable else {
            return .failure(FenceOperationRoutingError(
                message: "run_batch step command \"\(command.rawValue)\" is not batch-executable"
            ))
        }

        if let error = rawBatchShapeError(for: command, arguments: arguments) {
            return .failure(error)
        }

        return .success(NormalizedOperation(command: command, arguments: arguments))
    }

    private static func routeCommandNamed(
        _ name: String,
        arguments: [String: Any]
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

        return .success(NormalizedOperation(command: command, arguments: arguments))
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

    private static func rawBatchShapeError(
        for command: TheFence.Command,
        arguments: [String: Any]
    ) -> FenceOperationRoutingError? {
        guard let contract = TheFence.Command.mcpToolContract(named: command.rawValue),
              let selector = contract.selector else {
            return nil
        }

        let selectorKey = selector.parameter.key
        guard arguments[selectorKey] != nil else { return nil }

        let commandParameterKeys = Set(command.parameters.map(\.key))
        if !commandParameterKeys.contains(selectorKey) {
            return .init(
                message: "run_batch step \"\(command.rawValue)\" uses the MCP \(selectorKey) selector; " +
                    "use canonical Fence commands \(rawCommandList(contract.commands))."
            )
        }

        guard let selectorValue = arguments[selectorKey] as? String,
              selector.consumesValue(selectorValue),
              let selectedCommand = selector.command(for: selectorValue),
              selectedCommand != command else {
            return nil
        }
        return .init(
            message: "run_batch step \"\(command.rawValue)\" uses the MCP \(selectorValue) selector; " +
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
        arguments: [String: Any]
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        var operationArguments = arguments
        let rawValue: String?
        do {
            rawValue = try selectorValue(in: operationArguments, selector: selector)
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }

        guard let command = selector.command(for: rawValue) else {
            return .failure(FenceOperationRoutingError(
                message: "Unknown \(contract.name) selector value: \(rawValue ?? "missing")"
            ))
        }
        if selector.consumesValue(rawValue) {
            operationArguments.removeValue(forKey: selector.parameter.key)
        }
        return .success(NormalizedOperation(command: command, arguments: operationArguments))
    }

    private static func selectorValue(
        in arguments: [String: Any],
        selector: MCPToolSelector
    ) throws -> String? {
        let key = selector.parameter.key
        let rawValue = try arguments.schemaString(key)
        guard let enumValues = selector.parameter.enumValues else { return rawValue ?? selector.defaultValue }

        if let rawValue {
            guard enumValues.contains(rawValue) else {
                throw SchemaValidationError(
                    field: key,
                    observed: rawValue as Any,
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
}
