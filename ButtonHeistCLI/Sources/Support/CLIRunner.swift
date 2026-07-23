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

    enum RenderedCommandResult: Equatable {
        case text(String)
        case binary(Data)
        case failedText(String)
        case failedStatus(String)

        var isFailure: Bool {
            switch self {
            case .text, .binary:
                return false
            case .failedText, .failedStatus:
                return true
            }
        }
    }

    typealias JSONResponseRenderer = (FormattedResponse) throws -> Data

    private struct JSONResponseStatus: Decodable {
        let code: KnownFailureCode?
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

        if output(commandResult).isFailure {
            throw ExitCode.failure
        }
    }

    // MARK: - Output Formatting

    @discardableResult
    @ButtonHeistActor
    static func output(_ result: CommandResult) -> RenderedCommandResult {
        let rendered = renderedOutput(for: result)
        switch rendered {
        case .text(let text), .failedText(let text):
            writeOutput(text)
        case .binary(let data):
            writeBinaryOutput(data)
        case .failedStatus(let message):
            logStatus(message)
        }
        return rendered
    }

    static func renderedOutput(
        for result: CommandResult,
        jsonRenderer: JSONResponseRenderer = defaultJSONResponse
    ) -> RenderedCommandResult {
        switch result {
        case .response(let formatted):
            return renderedResponse(formatted, jsonRenderer: jsonRenderer)
        case .binary(let data):
            return .binary(data)
        }
    }

    private static func renderedResponse(
        _ formatted: FormattedResponse,
        jsonRenderer: JSONResponseRenderer
    ) -> RenderedCommandResult {
        let presenter = FenceResponsePresenter(profile: .summary)
        let responseFailed = formatted.envelope.response.isFailure
        switch formatted.format {
        case .human:
            let text = presenter.humanText(for: formatted.envelope.response)
            return responseFailed ? .failedText(text) : .text(text)
        case .compact:
            let text = presenter.compactText(for: formatted.envelope.response)
            return responseFailed ? .failedText(text) : .text(text)
        case .json:
            do {
                let data = try jsonRenderer(formatted)
                if let json = String(data: data, encoding: .utf8) {
                    let failed = responseFailed || isJSONRenderingFailure(data)
                    return failed ? .failedText(json) : .text(json)
                }
                return .failedStatus("Failed to encode JSON data as UTF-8")
            } catch {
                return .failedStatus("Failed to serialize response as JSON: \(error.localizedDescription)")
            }
        }
    }

    private static func defaultJSONResponse(_ formatted: FormattedResponse) throws -> Data {
        try FenceResponsePresenter(profile: .summary).jsonData(
            for: formatted.envelope.response,
            requestId: formatted.envelope.requestId
        )
    }

    private static func isJSONRenderingFailure(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(JSONResponseStatus.self, from: data).code)
            == .formattingJSONEncodingFailed
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
