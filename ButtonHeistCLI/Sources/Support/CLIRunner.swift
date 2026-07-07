import ArgumentParser
import Foundation
@_spi(ButtonHeistInternals) @_spi(ButtonHeistTooling) import ButtonHeist

/// Shared utility for standalone CLI commands that execute a single TheFence request.
enum CLIRunner {

    // MARK: - Nested Types

    typealias CommandResultMapper = (FenceResponse) throws -> CommandResult

    struct CommandExecution {
        let fence: TheFence
        let response: FenceResponse
    }

    struct ResponseEnvelope {
        let response: FenceResponse
        let requestId: PublicRequestId?

        init(response: FenceResponse, requestId: PublicRequestId? = nil) {
            self.response = response
            self.requestId = requestId
        }
    }

    struct FormattedResponse {
        let envelope: ResponseEnvelope
        let format: OutputFormat

        init(
            response: FenceResponse,
            format: OutputFormat,
            requestId: PublicRequestId? = nil
        ) {
            self.envelope = ResponseEnvelope(response: response, requestId: requestId)
            self.format = format
        }

        init(envelope: ResponseEnvelope, format: OutputFormat) {
            self.envelope = envelope
            self.format = format
        }
    }

    enum CommandResult {
        case response(FormattedResponse)
        case binary(Data)

        var isFailure: Bool {
            switch self {
            case .response(let formatted):
                return formatted.envelope.response.isFailure
            case .binary:
                return false
            }
        }
    }

    enum OutputPayload: Equatable {
        case text(String)
        case binary(Data)
        case status(String)
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
            let execution = try await execute(
                connection: connection,
                command: command,
                arguments: arguments,
                statusMessage: statusMessage
            )
            fence = execution.fence
            response = execution.response
        } catch {
            output(.response(FormattedResponse(response: .failure(error), format: fallbackFormat)))
            throw ExitCode.failure
        }
        defer { fence.stop() }

        let commandResult: CommandResult
        do {
            if let result {
                commandResult = try result(response)
            } else {
                commandResult = .response(FormattedResponse(response: response, format: fallbackFormat))
            }
        } catch {
            commandResult = .response(FormattedResponse(response: .failure(error), format: fallbackFormat))
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
    ) async throws -> CommandExecution {
        let fence = try await connect(connection: connection, statusMessage: statusMessage)
        do {
            let response = try await fence.execute(try fence.admit(command: command, arguments: arguments))
            return CommandExecution(fence: fence, response: response)
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
        output(.response(FormattedResponse(response: response, format: format)))
    }

    @ButtonHeistActor
    static func output(_ result: CommandResult) {
        switch renderedOutput(for: result) {
        case .text(let text):
            writeOutput(text)
        case .binary(let data):
            writeBinaryOutput(data)
        case .status(let message):
            logStatus(message)
        }
    }

    static func renderedOutput(for result: CommandResult) -> OutputPayload {
        switch result {
        case .response(let formatted):
            return renderedResponsePayload(formatted)
        case .binary(let data):
            return .binary(data)
        }
    }

    private static func renderedResponsePayload(_ formatted: FormattedResponse) -> OutputPayload {
        let presenter = FenceResponsePresenter(profile: .summary)
        switch formatted.format {
        case .human:
            return .text(presenter.humanText(for: formatted.envelope.response))
        case .compact:
            return .text(presenter.compactText(for: formatted.envelope.response))
        case .json:
            do {
                let data = try presenter.jsonData(
                    for: formatted.envelope.response,
                    requestId: formatted.envelope.requestId
                )
                if let json = String(data: data, encoding: .utf8) {
                    return .text(json)
                }
                return .status("Failed to encode JSON data as UTF-8")
            } catch {
                return .status("Failed to serialize response as JSON: \(error.localizedDescription)")
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
