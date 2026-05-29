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

/// Canonical Fence operation routed from external input.
public struct NormalizedOperation {
    public let command: TheFence.Command
    public let arguments: TheFence.CommandArgumentEnvelope
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

        return .success(NormalizedOperation(command: command, arguments: arguments))
    }

    public static func normalizeCommand(
        _ command: TheFence.Command,
        arguments: TheFence.CommandArgumentEnvelope
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        .success(NormalizedOperation(command: command, arguments: arguments))
    }

    public static func normalizeBatchStep(
        _ step: TheFence.CommandArgumentEnvelope
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        normalizeBatchStep(step, context: "run_batch step")
    }

    public static func normalizeBatchStep(
        _ step: TheFence.CommandArgumentEnvelope,
        context: String
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        normalizeCanonicalStep(
            step,
            context: context,
            isExecutable: \.isBatchExecutable
        )
    }

    public static func normalizeCommandEnvelope(
        _ arguments: TheFence.CommandArgumentEnvelope,
        context: String
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        normalizeCanonicalStep(
            arguments,
            context: context,
            isExecutable: nil
        )
    }

    public static func normalizePlaybackStep(commandName: String) -> Result<TheFence.Command, FenceOperationRoutingError> {
        normalizeTypedPlaybackStep(
            commandName: commandName,
            context: "heist step"
        )
    }

    private static func normalizeCanonicalStep(
        _ step: TheFence.CommandArgumentEnvelope,
        context: String,
        isExecutable: KeyPath<TheFence.Command, Bool>?
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        let commandName: String
        do {
            commandName = try step.requiredSchemaString("command")
        } catch let error as SchemaValidationError {
            return .failure(FenceOperationRoutingError(message: error.message))
        } catch {
            return .failure(FenceOperationRoutingError(message: error.localizedDescription))
        }

        return normalizeCanonicalStep(
            commandName: commandName,
            arguments: step.dropping("command"),
            context: context,
            isExecutable: isExecutable
        )
    }

    private static func normalizeCanonicalStep(
        commandName: String,
        arguments: TheFence.CommandArgumentEnvelope,
        context: String,
        isExecutable: KeyPath<TheFence.Command, Bool>?
    ) -> Result<NormalizedOperation, FenceOperationRoutingError> {
        guard let command = TheFence.Command(rawValue: commandName) else {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command must be a canonical TheFence.Command; unknown command \"\(commandName)\""
            ))
        }

        if let isExecutable, !command[keyPath: isExecutable] {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command \"\(command.rawValue)\" is not supported"
            ))
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

        guard command.isBatchExecutable else {
            return .failure(FenceOperationRoutingError(
                message: "\(context) command \"\(command.rawValue)\" is not batch-executable"
            ))
        }

        return .success(command)
    }

}
