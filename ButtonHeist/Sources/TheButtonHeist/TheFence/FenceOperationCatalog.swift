import Foundation

/// Failure produced while normalizing an external tool name into a Fence command.
///
/// This stays separate from `FenceError`: it describes pre-dispatch routing
/// failures before a concrete Fence command exists.
public struct FenceOperationRoutingError: Error, LocalizedError, Sendable {
    public let message: String

    public var errorDescription: String? { message }
}

/// Shared routing table for MCP tool calls and batch steps.
public enum FenceOperationCatalog {
    public static func normalizeToolCall(
        name: String,
        arguments: [String: Any],
        allowRawFenceCommands: Bool = false
    ) -> Result<[String: Any], FenceOperationRoutingError> {
        switch name {
        case "gesture":
            return routeGesture(arguments)

        case TheFence.Command.scroll.rawValue:
            return routeScroll(arguments)

        case TheFence.Command.editAction.rawValue:
            return routeEditAction(arguments)

        default:
            return routeCommandNamed(
                name,
                arguments: arguments,
                allowRawFenceCommands: allowRawFenceCommands
            )
        }
    }

    public static func normalizeBatchStep(
        _ step: [String: Any]
    ) -> Result<[String: Any], FenceOperationRoutingError> {
        let command: String
        do {
            command = try step.requiredSchemaString("command")
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }

        var arguments = step
        arguments.removeValue(forKey: "command")
        return normalizeToolCall(
            name: command,
            arguments: arguments,
            allowRawFenceCommands: true
        )
    }

    private static func routeCommandNamed(
        _ name: String,
        arguments: [String: Any],
        allowRawFenceCommands: Bool
    ) -> Result<[String: Any], FenceOperationRoutingError> {
        guard let command = TheFence.Command(rawValue: name) else {
            return .failure(FenceOperationRoutingError(message: "Unknown tool: \(name)"))
        }
        guard allowRawFenceCommands || command.mcpExposure == .directTool else {
            if let message = groupedToolRoutingMessage(for: command) {
                return .failure(FenceOperationRoutingError(message: message))
            }
            return .failure(FenceOperationRoutingError(message: "Unknown tool: \(name)"))
        }

        var request = arguments
        request["command"] = command.rawValue
        return .success(request)
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

    private static func routeGesture(_ arguments: [String: Any]) -> Result<[String: Any], FenceOperationRoutingError> {
        var request = arguments
        let gestureType: GestureType
        do {
            gestureType = try request.requiredSchemaEnum("type", as: GestureType.self)
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }
        request.removeValue(forKey: "type")
        guard let command = TheFence.Command(rawValue: gestureType.rawValue) else {
            return .failure(FenceOperationRoutingError(message: "Unknown gesture command: \(gestureType.rawValue)"))
        }
        request["command"] = command.rawValue
        return .success(request)
    }

    private static func routeScroll(_ arguments: [String: Any]) -> Result<[String: Any], FenceOperationRoutingError> {
        var request = arguments
        let scrollMode: ScrollMode
        do {
            scrollMode = try request.schemaEnum("mode", as: ScrollMode.self) ?? .page
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }
        request.removeValue(forKey: "mode")
        guard let command = TheFence.Command(rawValue: scrollMode.canonicalCommand) else {
            return .failure(FenceOperationRoutingError(message: "Unknown scroll command: \(scrollMode.canonicalCommand)"))
        }
        request["command"] = command.rawValue
        return .success(request)
    }

    private static func routeEditAction(_ arguments: [String: Any]) -> Result<[String: Any], FenceOperationRoutingError> {
        var request = arguments
        if let action = request["action"] as? String, action == "dismiss" {
            request.removeValue(forKey: "action")
            request["command"] = TheFence.Command.dismissKeyboard.rawValue
        } else {
            request["command"] = TheFence.Command.editAction.rawValue
        }
        return .success(request)
    }
}
