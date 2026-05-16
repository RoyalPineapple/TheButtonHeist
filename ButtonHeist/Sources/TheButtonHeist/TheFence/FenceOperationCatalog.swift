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

        case "scroll":
            return routeScroll(arguments)

        case "edit_action":
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
            return .failure(FenceOperationRoutingError(message: "Unknown tool: \(name)"))
        }

        var request = arguments
        request["command"] = name
        return .success(request)
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
        request["command"] = gestureType.rawValue
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
        request["command"] = scrollMode.canonicalCommand
        return .success(request)
    }

    private static func routeEditAction(_ arguments: [String: Any]) -> Result<[String: Any], FenceOperationRoutingError> {
        var request = arguments
        if let action = request["action"] as? String, action == "dismiss" {
            request.removeValue(forKey: "action")
            request["command"] = "dismiss_keyboard"
        } else {
            request["command"] = "edit_action"
        }
        return .success(request)
    }
}
