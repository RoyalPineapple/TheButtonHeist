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

/// Routed public command input before admission into TheFence's typed runtime.
@_spi(ButtonHeistTooling) public struct FenceCommandInput: Sendable {
    @_spi(ButtonHeistTooling) public let command: TheFence.Command
    @_spi(ButtonHeistTooling) public let arguments: TheFence.CommandArgumentEnvelope

    @_spi(ButtonHeistTooling) public init(command: TheFence.Command, arguments: TheFence.CommandArgumentEnvelope) {
        self.command = command
        self.arguments = arguments
    }

    @_spi(ButtonHeistTooling) public func validatePublicContract() throws {
        guard command.descriptor.isPublicRequestContract else {
            throw SchemaValidationError(
                field: "command",
                observed: "string \"\(command.rawValue)\"",
                expected: "public command for The Button Heist"
            )
        }

        let metadataKeys = Set([FenceParameterKey.requestId.rawValue])
        let allowedKeys = metadataKeys.union(command.descriptor.topLevelParameterKeys)
        guard let unexpectedKey = arguments.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            try command.descriptor.validatePublicRequestArguments(arguments)
            return
        }

        throw SchemaValidationError(
            field: arguments.field(forUnknownKey: unexpectedKey),
            observed: arguments.observedDescription(forUnknownKey: unexpectedKey) ?? "missing",
            expected: "valid \(command.rawValue) parameter"
        )
    }
}

/// Fully admitted operation ready to enter TheFence's execution pipeline.
@_spi(ButtonHeistTooling) public struct FenceOperationRequest: Sendable {
    let parsed: TheFence.ParsedRequest

    @_spi(ButtonHeistTooling) public var command: TheFence.Command {
        parsed.command
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
    ) -> Result<FenceCommandInput, FenceOperationRoutingError> {
        switch routeToolCall(named: name) {
        case .success(let command):
            return .success(FenceCommandInput(command: command, arguments: arguments))
        case .failure(let error):
            return .failure(error)
        }
    }

    static func routeCommandEnvelope(
        _ arguments: TheFence.CommandArgumentEnvelope,
        context: String
    ) -> Result<FenceCommandInput, FenceOperationRoutingError> {
        routeCanonicalStep(arguments, context: context, isExecutable: nil)
    }

    static func routeCLICommandEnvelope(
        _ arguments: TheFence.CommandArgumentEnvelope,
        context: String
    ) -> Result<FenceCommandInput, FenceOperationRoutingError> {
        routeCanonicalStep(
            arguments,
            context: context,
            isExecutable: { $0.descriptor.projection.cliExposure == .directCommand }
        )
    }
}

private extension TheFence.Command {
    static func routeCanonicalStep(
        _ step: TheFence.CommandArgumentEnvelope,
        context: String,
        isExecutable: ((Self) -> Bool)?
    ) -> Result<FenceCommandInput, FenceOperationRoutingError> {
        let commandName: String
        do {
            commandName = try step.requiredValue(FenceParameters.commandName)
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
            arguments: step.dropping(.command),
            context: context,
            isExecutable: isExecutable
        )
    }

    static func routeCanonicalStep(
        commandName: String,
        arguments: TheFence.CommandArgumentEnvelope,
        context: String,
        isExecutable: ((Self) -> Bool)?
    ) -> Result<FenceCommandInput, FenceOperationRoutingError> {
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

        return .success(FenceCommandInput(command: command, arguments: arguments))
    }
}
