import Foundation
import TheScore

/// Failure produced while routing an external command name into a Fence command.
///
/// This stays separate from `FenceError`: it describes pre-dispatch routing
/// failures before a concrete Fence command exists.
@_spi(ButtonHeistTooling) public struct FenceOperationRoutingError: Error, LocalizedError, Sendable {
    @_spi(ButtonHeistTooling) public let message: String
    @_spi(ButtonHeistTooling) public let details: FailureDetails

    @_spi(ButtonHeistTooling) public init(message: String, details: FailureDetails = FailureDetails(code: .requestInvalid)) {
        self.message = message
        self.details = details
    }

    public var errorDescription: String? { message }
}

/// Fully routed operation ready to enter TheFence's execution pipeline.
@_spi(ButtonHeistTooling) public struct FenceOperationRequest: Sendable {
    @_spi(ButtonHeistTooling) public let command: TheFence.Command
    @_spi(ButtonHeistTooling) public let arguments: TheFence.CommandArgumentEnvelope

    @_spi(ButtonHeistTooling) public init(command: TheFence.Command, arguments: TheFence.CommandArgumentEnvelope) {
        self.command = command
        self.arguments = arguments
    }
}

@_spi(ButtonHeistTooling) public extension TheFence.Command {
    static func routeToolCall(named name: String) -> Result<Self, FenceOperationRoutingError> {
        guard let command = Self(rawValue: name),
              command.descriptor.mcpExposure == .directTool else {
            return .failure(FenceOperationRoutingError(message: "Unknown tool: \(name)"))
        }

        return .success(command)
    }

    static func routeToolRequest(
        named name: String,
        arguments: TheFence.CommandArgumentEnvelope
    ) -> Result<FenceOperationRequest, FenceOperationRoutingError> {
        switch routeToolCall(named: name) {
        case .success(let command):
            return .success(FenceOperationRequest(command: command, arguments: arguments))
        case .failure(let error):
            return .failure(error)
        }
    }

    static func routeCommandEnvelope(
        _ arguments: TheFence.CommandArgumentEnvelope,
        context: String
    ) -> Result<FenceOperationRequest, FenceOperationRoutingError> {
        routeCanonicalStep(arguments, context: context, isExecutable: nil)
    }

    static func routeCLICommandEnvelope(
        _ arguments: TheFence.CommandArgumentEnvelope,
        context: String
    ) -> Result<FenceOperationRequest, FenceOperationRoutingError> {
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
            return .failure(FenceOperationRoutingError(
                message: error.message,
                details: FailureDetails(code: .requestValidationError)
            ))
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
    ) -> Result<FenceOperationRequest, FenceOperationRoutingError> {
        let commandName: String
        do {
            commandName = try step.requiredSchemaString("command")
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(
                message: error.message,
                details: FailureDetails(code: .requestValidationError)
            ))
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
    ) -> Result<FenceOperationRequest, FenceOperationRoutingError> {
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

        return .success(FenceOperationRequest(command: command, arguments: arguments))
    }
}
