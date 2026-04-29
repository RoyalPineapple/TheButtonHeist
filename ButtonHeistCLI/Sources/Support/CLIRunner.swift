import Foundation
import Darwin
import ButtonHeist

/// Shared utility for standalone CLI commands that execute a single TheFence request.
///
/// This eliminates the DeviceConnector boilerplate by routing all commands through
/// `TheFence.execute(request:)` — the same path the session REPL and MCP server use.
enum CLIRunner {

    /// Execute a single TheFence command and output the formatted response.
    ///
    /// Creates a TheFence, connects to the device, executes the request,
    /// formats the response, and disconnects. For standalone (non-session) commands.
    ///
    /// If the response indicates a failed action, exits with code 1.
    @ButtonHeistActor
    static func run(
        connection: ConnectionOptions,
        format: OutputFormat?,
        request: [String: Any],
        statusMessage: String? = nil
    ) async throws {
        let fence = makeFence(connection: connection)
        defer { fence.stop() }

        try await fence.start()

        if let statusMessage, !connection.quiet {
            logStatus(statusMessage)
        }

        let response = try await fence.execute(request: request)
        let effectiveFormat = format ?? .auto
        outputResponse(response, format: effectiveFormat)
        exitOnActionFailure(response)
    }

    /// Execute a single TheFence command and return the raw FenceResponse
    /// for commands that need custom post-processing (e.g., saving files).
    ///
    /// Caller is responsible for calling `fence.stop()` when done.
    @ButtonHeistActor
    static func execute(
        connection: ConnectionOptions,
        request: [String: Any],
        statusMessage: String? = nil
    ) async throws -> (fence: TheFence, response: FenceResponse) {
        let fence = makeFence(connection: connection)

        do {
            try await fence.start()
        } catch {
            fence.stop()
            throw error
        }

        if let statusMessage, !connection.quiet {
            logStatus(statusMessage)
        }

        do {
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

    // MARK: - Private

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

    /// Exit with code 1 if the command failed, including unmet expectations.
    @ButtonHeistActor
    private static func exitOnActionFailure(_ response: FenceResponse) {
        if response.isFailure {
            Darwin.exit(1)
        }
    }
}
