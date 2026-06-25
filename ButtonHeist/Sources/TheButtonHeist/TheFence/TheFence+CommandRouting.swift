import Foundation
import TheScore

/// Failure produced while routing an external command name into a Fence command.
///
/// This stays separate from `FenceError`: it describes pre-dispatch routing
/// failures before a concrete Fence command exists.
public struct FenceOperationRoutingError: Error, LocalizedError, Sendable {
    public let message: String

    public var errorDescription: String? { message }
}

public extension TheFence.Command {
    static func routeToolCall(named name: String) -> Result<Self, FenceOperationRoutingError> {
        guard let command = Self(rawValue: name),
              command.descriptor.mcpExposure == .directTool else {
            return .failure(FenceOperationRoutingError(message: "Unknown tool: \(name)"))
        }

        return .success(command)
    }

    static func routeCommandEnvelope(
        _ arguments: TheFence.CommandArgumentEnvelope,
        context: String
    ) -> Result<(command: Self, arguments: TheFence.CommandArgumentEnvelope), FenceOperationRoutingError> {
        routeCanonicalStep(arguments, context: context, isExecutable: nil)
    }

    static func routeCLICommandEnvelope(
        _ arguments: TheFence.CommandArgumentEnvelope,
        context: String
    ) -> Result<(command: Self, arguments: TheFence.CommandArgumentEnvelope), FenceOperationRoutingError> {
        let routed = routeCanonicalStep(
            arguments,
            context: context,
            isExecutable: { $0.descriptor.projection.cliExposure == .directCommand }
        )
        guard case .success(let value) = routed else { return routed }
        do {
            try value.command.descriptor.validatePublicRequestArguments(value.arguments)
            return .success(value)
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }
    }

}

private extension TheFence.Command {
    static func routeCanonicalStep(
        _ step: TheFence.CommandArgumentEnvelope,
        context: String,
        isExecutable: ((Self) -> Bool)?
    ) -> Result<(command: Self, arguments: TheFence.CommandArgumentEnvelope), FenceOperationRoutingError> {
        let commandName: String
        do {
            commandName = try step.requiredSchemaString("command")
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }

        return routeCanonicalStep(
            commandName: commandName,
            arguments: step.dropping("command"),
            context: context,
            isExecutable: isExecutable
        )
    }

    static func routeCanonicalStep(
        commandName: String,
        arguments: TheFence.CommandArgumentEnvelope,
        context: String,
        isExecutable: ((Self) -> Bool)?
    ) -> Result<(command: Self, arguments: TheFence.CommandArgumentEnvelope), FenceOperationRoutingError> {
        guard let command = Self(rawValue: commandName) else {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command must be a canonical TheFence.Command; unknown command \"\(commandName)\""
            ))
        }

        if let isExecutable, !isExecutable(command) {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command \"\(command.rawValue)\" is not supported"
            ))
        }

        return .success((command: command, arguments: arguments))
    }
}
