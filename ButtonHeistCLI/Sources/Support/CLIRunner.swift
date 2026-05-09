import ArgumentParser
import Foundation
import ButtonHeist

/// Shared utility for standalone CLI commands that execute a single TheFence request.
enum CLIRunner {

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
        request: [String: Any],
        statusMessage: String? = nil
    ) async throws {
        let (fence, response) = try await execute(
            connection: connection,
            request: request,
            statusMessage: statusMessage
        )
        defer { fence.stop() }

        outputResponse(response, format: format ?? .auto)
        if response.isFailure {
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
        request: [String: Any],
        statusMessage: String? = nil
    ) async throws -> (fence: TheFence, response: FenceResponse) {
        let fence = makeFence(connection: connection)
        do {
            try await fence.start()
            if let statusMessage, !connection.quiet {
                logStatus(statusMessage)
            }
            let response = try await fence.execute(request: request)
            return (fence, response)
        } catch {
            fence.stop()
            throw error
        }
    }

    // MARK: - Output Formatting

    @ButtonHeistActor
    static func outputResponse(_ response: FenceResponse, format: OutputFormat) {
        switch format {
        case .human:
            writeOutput(response.humanFormatted())
        case .compact:
            writeOutput(response.compactFormatted())
        case .json:
            if let dictionary = response.jsonDict() {
                do {
                    let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])
                    if let json = String(data: data, encoding: .utf8) {
                        writeOutput(json)
                    } else {
                        logStatus("Failed to encode JSON data as UTF-8")
                    }
                } catch {
                    logStatus("Failed to serialize response as JSON: \(error.localizedDescription)")
                }
            } else {
                logStatus("Failed to serialize response as JSON")
            }
        }
    }

    // MARK: - Private Helpers

    @ButtonHeistActor
    private static func makeFence(connection: ConnectionOptions) -> TheFence {
        let config = EnvironmentConfig.resolve(
            deviceFilter: connection.device,
            token: connection.token,
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
