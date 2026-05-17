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
/// routing edge. The dictionary form is only reconstructed when crossing into
/// legacy APIs that still accept raw request dictionaries.
public struct NormalizedOperation {
    public let command: TheFence.Command
    public let arguments: [String: Any]

    public init(command: TheFence.Command, arguments: [String: Any]) {
        var sanitizedArguments = arguments
        sanitizedArguments.removeValue(forKey: "command")
        self.command = command
        self.arguments = sanitizedArguments
    }

    public var legacyRequestDictionary: [String: Any] {
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
        switch name {
        case "gesture":
            return routeGesture(arguments)

        case TheFence.Command.scroll.rawValue:
            return routeScroll(arguments)

        case TheFence.Command.editAction.rawValue:
            return routeEditAction(arguments)

        default:
            return routeCommandNamed(name, arguments: arguments)
        }
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
                message: "run_batch step command must be a raw TheFence.Command; unknown command \"\(commandName)\""
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
        case .groupedUnder("gesture"):
            return groupedToolRoutingMessage(
                rawToolName: command.rawValue,
                groupedToolName: "gesture",
                selectorName: "type",
                selectorValue: command.rawValue
            )

        case .groupedUnder(TheFence.Command.scroll.rawValue):
            guard let mode = ScrollMode.allCases.first(where: { $0.canonicalCommand == command.rawValue }) else {
                return nil
            }
            return groupedToolRoutingMessage(
                rawToolName: command.rawValue,
                groupedToolName: TheFence.Command.scroll.rawValue,
                selectorName: "mode",
                selectorValue: mode.rawValue
            )

        case .groupedUnder(TheFence.Command.editAction.rawValue) where command == .dismissKeyboard:
            return groupedToolRoutingMessage(
                rawToolName: command.rawValue,
                groupedToolName: TheFence.Command.editAction.rawValue,
                selectorName: "action",
                selectorValue: "dismiss"
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
        switch command {
        case .scroll where arguments["mode"] != nil:
            return .init(
                message: "run_batch step \"scroll\" uses the MCP mode selector; " +
                    "use raw Fence commands scroll, scroll_to_visible, element_search, or scroll_to_edge."
            )

        case .editAction where arguments["action"] as? String == "dismiss":
            return .init(message: "run_batch step \"edit_action\" uses the MCP dismiss selector; use raw Fence command dismiss_keyboard.")

        default:
            return nil
        }
    }

    private static func routeGesture(_ arguments: [String: Any]) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        var operationArguments = arguments
        let gestureType: GestureType
        do {
            gestureType = try operationArguments.requiredSchemaEnum("type", as: GestureType.self)
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }
        operationArguments.removeValue(forKey: "type")
        guard let command = TheFence.Command(rawValue: gestureType.rawValue) else {
            return .failure(FenceOperationRoutingError(message: "Unknown gesture command: \(gestureType.rawValue)"))
        }
        return .success(NormalizedOperation(command: command, arguments: operationArguments))
    }

    private static func routeScroll(_ arguments: [String: Any]) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        var operationArguments = arguments
        let scrollMode: ScrollMode
        do {
            scrollMode = try operationArguments.schemaEnum("mode", as: ScrollMode.self) ?? .page
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }
        operationArguments.removeValue(forKey: "mode")
        guard let command = TheFence.Command(rawValue: scrollMode.canonicalCommand) else {
            return .failure(FenceOperationRoutingError(message: "Unknown scroll command: \(scrollMode.canonicalCommand)"))
        }
        return .success(NormalizedOperation(command: command, arguments: operationArguments))
    }

    private static func routeEditAction(_ arguments: [String: Any]) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        var operationArguments = arguments
        if let action = operationArguments["action"] as? String, action == "dismiss" {
            operationArguments.removeValue(forKey: "action")
            return .success(NormalizedOperation(
                command: .dismissKeyboard,
                arguments: operationArguments
            ))
        } else {
            return .success(NormalizedOperation(command: .editAction, arguments: operationArguments))
        }
    }
}
