import ArgumentParser
import Foundation
@_spi(ButtonHeistInternals) @_spi(ButtonHeistTooling) import ButtonHeist

/// Shared utility for standalone CLI commands that execute a single TheFence request.
enum CLIRunner {

    // MARK: - Nested Types

    typealias CommandResultProjection = @ButtonHeistActor (TheFence, FenceResponse) throws -> CommandResult

    enum ExecutionMode: Equatable {
        case connected
        case direct
    }

    struct CommandDescriptor {
        let fenceDescriptor: FenceCommandDescriptor
        let connection: ConnectionOptions
        let format: OutputFormat?
        let arguments: TheFence.CommandArgumentEnvelope
        let executionMode: ExecutionMode
        let statusMessage: String?
        let configuration: EnvironmentConfig?
        let cleanup: () -> Void
        let result: CommandResultProjection?

        init(
            fenceDescriptor: FenceCommandDescriptor,
            connection: ConnectionOptions,
            format: OutputFormat?,
            arguments: TheFence.CommandArgumentEnvelope,
            executionMode: ExecutionMode = .connected,
            statusMessage: String? = nil,
            configuration: EnvironmentConfig? = nil,
            cleanup: @escaping () -> Void = {},
            result: CommandResultProjection? = nil
        ) {
            self.fenceDescriptor = fenceDescriptor
            self.connection = connection
            self.format = format
            self.arguments = arguments
            self.executionMode = executionMode
            self.statusMessage = statusMessage
            self.configuration = configuration
            self.cleanup = cleanup
            self.result = result
        }
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
    static func run(_ descriptor: CommandDescriptor) async throws {
        defer { descriptor.cleanup() }
        let fallbackFormat = descriptor.format ?? .auto
        let fence: TheFence
        let response: FenceResponse
        do {
            fence = try makeFence(descriptor: descriptor)
            do {
                if descriptor.executionMode == .connected {
                    try await fence.start()
                }
                if let statusMessage = descriptor.statusMessage, !isQuiet(descriptor) {
                    logStatus(statusMessage)
                }
                response = try await fence.execute(try fence.admit(FenceCommandInput(
                    command: descriptor.fenceDescriptor.command,
                    arguments: descriptor.arguments
                )))
            } catch {
                fence.stop()
                throw error
            }
        } catch {
            output(.response(FormattedResponse(response: .failure(error), format: fallbackFormat)))
            throw ExitCode.failure
        }
        defer { fence.stop() }

        let commandResult: CommandResult
        do {
            if let result = descriptor.result {
                commandResult = try result(fence, response)
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

    // MARK: - Output Formatting

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
    private static func makeFence(descriptor: CommandDescriptor) throws -> TheFence {
        let config: EnvironmentConfig
        if let configuration = descriptor.configuration {
            config = configuration
        } else if descriptor.executionMode == .direct {
            config = try EnvironmentConfig.resolve(autoReconnect: false)
        } else {
            let connection = descriptor.connection
            config = try EnvironmentConfig.resolve(
                deviceFilter: connection.device,
                token: connection.token,
                connectionTimeout: connection.connectTimeout,
                autoReconnect: false
            )
        }
        let fence = TheFence(configuration: config.fenceConfiguration)
        let quiet = isQuiet(descriptor)
        fence.onStatus = { message in
            if !quiet { logStatus(message) }
        }
        return fence
    }

    private static func isQuiet(_ descriptor: CommandDescriptor) -> Bool {
        descriptor.executionMode == .direct || descriptor.connection.quiet
    }
}
