import ArgumentParser
import Foundation
import ButtonHeist

/// Shared utility for standalone CLI commands that execute a single TheFence request.
enum CLIRunner {

    // MARK: - Nested Types

    typealias CommandResultMapper = (FenceResponse) throws -> CommandResult

    enum CommandResult {
        case response(FenceResponse, format: OutputFormat)
        case binary(Data)

        var isFailure: Bool {
            switch self {
            case .response(let response, _):
                return response.isFailure
            case .binary:
                return false
            }
        }
    }

    // MARK: - Command Execution

    /// Execute a single TheFence command, format the response, and signal a non-zero
    /// exit code via `ExitCode.failure` when the action fails.
    ///
    /// Use this for the common "send one command, print the response, return" path.
    /// `ExitCode.failure` propagates up through ArgumentParser so the process exits
    /// with status 1 — but unwinds normally so any caller `defer` blocks still fire.
    @ButtonHeistActor
    static func run(
        connection: ConnectionOptions,
        format: OutputFormat?,
        command: TheFence.Command,
        arguments: TheFence.CommandArgumentEnvelope,
        statusMessage: String? = nil,
        result: CommandResultMapper? = nil
    ) async throws {
        let fallbackFormat = format ?? .auto
        let fence: TheFence
        let response: FenceResponse
        do {
            (fence, response) = try await execute(
                connection: connection,
                command: command,
                arguments: arguments,
                statusMessage: statusMessage
            )
        } catch {
            output(.response(.failure(error), format: fallbackFormat))
            throw ExitCode.failure
        }
        defer { fence.stop() }

        let commandResult: CommandResult
        do {
            if let result {
                commandResult = try result(response)
            } else {
                commandResult = .response(response, format: fallbackFormat)
            }
        } catch {
            commandResult = .response(.failure(error), format: fallbackFormat)
        }

        output(commandResult)
        if commandResult.isFailure {
            throw ExitCode.failure
        }
    }

    /// Execute a single TheFence command and return the raw FenceResponse
    /// for commands that need custom post-processing (e.g., saving files).
    ///
    /// Caller is responsible for calling `fence.stop()` when done. The fence is
    /// stopped automatically if `start` or `execute` throws.
    @ButtonHeistActor
    static func execute(
        connection: ConnectionOptions,
        command: TheFence.Command,
        arguments: TheFence.CommandArgumentEnvelope,
        statusMessage: String? = nil
    ) async throws -> (fence: TheFence, response: FenceResponse) {
        let fence = try await connect(connection: connection, statusMessage: statusMessage)
        do {
            let response = try await fence.execute(command: command, arguments: arguments)
            return (fence, response)
        } catch {
            fence.stop()
            throw error
        }
    }

    /// Connect a fence without dispatching any command, for callers that drive
    /// TheFence's higher-level primitives directly (e.g. `recordToCompletion`).
    ///
    /// Caller is responsible for calling `fence.stop()` when done. The fence is
    /// stopped automatically if `start` throws.
    @ButtonHeistActor
    static func connect(
        connection: ConnectionOptions,
        statusMessage: String? = nil
    ) async throws -> TheFence {
        let fence = try makeFence(connection: connection)
        do {
            try await fence.start()
            if let statusMessage, !connection.quiet {
                logStatus(statusMessage)
            }
            return fence
        } catch {
            fence.stop()
            throw error
        }
    }

    // MARK: - Output Formatting

    @ButtonHeistActor
    static func outputResponse(_ response: FenceResponse, format: OutputFormat) {
        output(.response(response, format: format))
    }

    @ButtonHeistActor
    static func output(_ result: CommandResult) {
        switch result {
        case .response(let response, let format):
            outputResponsePayload(response, format: format)
        case .binary(let data):
            writeBinaryOutput(data)
        }
    }

    @ButtonHeistActor
    private static func outputResponsePayload(_ response: FenceResponse, format: OutputFormat) {
        let presenter = FenceResponsePresenter(profile: .summary)
        switch format {
        case .human:
            writeOutput(presenter.humanText(for: response))
        case .compact:
            writeOutput(presenter.compactText(for: response))
        case .json:
            do {
                let data = try presenter.jsonData(for: response)
                if let json = String(data: data, encoding: .utf8) {
                    writeOutput(json)
                } else {
                    logStatus("Failed to encode JSON data as UTF-8")
                }
            } catch {
                logStatus("Failed to serialize response as JSON: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private Helpers

    @ButtonHeistActor
    private static func makeFence(connection: ConnectionOptions) throws -> TheFence {
        let config = try EnvironmentConfig.resolve(
            deviceFilter: connection.device,
            token: connection.token,
            connectionTimeout: connection.connectTimeout,
            autoReconnect: false
        )
        let fence = TheFence(configuration: config.fenceConfiguration)
        let quiet = connection.quiet
        fence.onStatus = { message in
            if !quiet { logStatus(message) }
        }
        return fence
    }
}
