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
    public func argumentValue(_ key: String) -> HeistValue? {
        request.argumentEnvelopeForRequestDecoding().argumentValues[key]
    }

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
        guard let command = TheFence.Command(rawValue: name),
              command.descriptor.mcpExposure == .directTool else {
            return .failure(FenceOperationRoutingError(message: "Unknown tool: \(name)"))
        }

        return normalizeToolOperation(command: command, arguments: arguments)
    }

    public static func normalizeCommand(
        _ command: TheFence.Command,
        arguments: TheFence.CommandArgumentEnvelope
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        normalizeToolOperation(command: command, arguments: arguments)
    }

    public static func normalizeBatchStep(
        _ step: TheFence.CommandArgumentObject
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        normalizeCanonicalStep(
            step,
            context: "run_batch step",
            isExecutable: \.isBatchExecutable
        )
    }

    public static func normalizePlaybackStep(commandName: String) -> Result<TheFence.Command, FenceOperationRoutingError> {
        normalizeTypedPlaybackStep(
            commandName: commandName,
            context: "heist step"
        )
    }

    public static func normalizePlaybackStep(
        commandName: String,
        arguments: TheFence.CommandArgumentEnvelope
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        switch normalizeTypedPlaybackStep(commandName: commandName, context: "heist step") {
        case .success(let command):
            return normalizeToolOperation(command: command, arguments: arguments)
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func normalizeCanonicalStep(
        _ step: TheFence.CommandArgumentObject,
        context: String,
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
            isExecutable: isExecutable
        )
    }

    private static func normalizeCanonicalStep(
        commandName: String,
        arguments: TheFence.CommandArgumentEnvelope,
        context: String,
        isExecutable: KeyPath<TheFence.Command, Bool>
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        guard let command = TheFence.Command(rawValue: commandName) else {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command must be a canonical TheFence.Command; unknown command \"\(commandName)\""
            ))
        }

        guard command[keyPath: isExecutable] else {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command \"\(command.rawValue)\" is not supported"
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

    private static func canonicalShapeError(
        for command: TheFence.Command,
        arguments: some TheFence.CommandArgumentReadable,
        context _: String
    ) -> FenceOperationRoutingError? {
        let commandParameters = command.parameters
        let commandParameterKeys = Set(commandParameters.map(\.key))
        if let unsupportedKey = arguments.keys.filter({ !commandParameterKeys.contains($0) }).sorted().first {
            return .init(message: "Unknown parameter '\(unsupportedKey)' for \(command.rawValue)")
        }

        for parameter in commandParameters {
            guard let enumValues = parameter.enumValues,
                  arguments.keys.contains(parameter.key) else {
                continue
            }
            do {
                guard let value = try arguments.schemaString(parameter.key) else { continue }
                guard enumValues.contains(value) else {
                    return .init(message: SchemaValidationError(
                        field: parameter.key,
                        observed: "string \"\(value)\"",
                        expected: SchemaValidationError.expectedEnumValues(enumValues)
                    ).message)
                }
            } catch let error as SchemaValidationError {
                return .init(message: error.message)
            } catch {
                return .init(message: error.localizedDescription)
            }
        }

        return nil
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

}

private extension TheFence.Command {
    var acceptsExpectationPayload: Bool {
        parameters.contains { $0.key == FenceParameterKey.expect.rawValue }
    }
}
