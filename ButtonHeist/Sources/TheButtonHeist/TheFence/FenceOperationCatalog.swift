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
        guard let command = step["command"] as? String else {
            return .failure(FenceOperationRoutingError(message: "Missing required command"))
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
        guard let rawType = request.removeValue(forKey: "type") as? String else {
            return .failure(FenceOperationRoutingError(message: "Missing required parameter: type"))
        }
        guard let gestureType = GestureType(rawValue: rawType) else {
            let valid = GestureType.allCases.map(\.rawValue).joined(separator: ", ")
            return .failure(FenceOperationRoutingError(message: "Unknown gesture type: \(rawType). Valid: \(valid)"))
        }
        request["command"] = gestureType.rawValue
        return .success(request)
    }

    private static func routeScroll(_ arguments: [String: Any]) -> Result<[String: Any], FenceOperationRoutingError> {
        var request = arguments
        let rawMode = (request.removeValue(forKey: "mode") as? String) ?? ScrollMode.page.rawValue
        guard let scrollMode = ScrollMode(rawValue: rawMode) else {
            let valid = ScrollMode.allCases.map(\.rawValue).joined(separator: ", ")
            return .failure(FenceOperationRoutingError(message: "Unknown scroll mode: \(rawMode). Valid: \(valid)"))
        }
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
