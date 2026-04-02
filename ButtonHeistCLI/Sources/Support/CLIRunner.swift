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
        outputResponse(response, format: effectiveFormat, fence: fence)
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

        try await fence.start()

        if let statusMessage, !connection.quiet {
            logStatus(statusMessage)
        }

        let response = try await fence.execute(request: request)
        return (fence, response)
    }

    // MARK: - Output Formatting

    @ButtonHeistActor
    static func outputResponse(_ response: FenceResponse, format: OutputFormat, fence: TheFence? = nil) {
        switch format {
        case .human:
            let text = response.humanFormatted()
            writeOutput(fence?.applyTelemetry(to: text) ?? text)
        case .compact:
            let text = response.compactFormatted()
            writeOutput(fence?.applyTelemetry(to: text) ?? text)
        case .json:
            if var dictionary = response.jsonDict() {
                if let fence,
                   let serialized = try? JSONSerialization.data(withJSONObject: dictionary, options: []),
                   let preview = String(data: serialized, encoding: .utf8),
                   let telemetry = fence.telemetryDict(for: preview) {
                    dictionary["_telemetry"] = telemetry
                }
                if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8) {
                    writeOutput(json)
                }
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

    /// Exit with code 1 if the response wraps a failed action.
    @ButtonHeistActor
    private static func exitOnActionFailure(_ response: FenceResponse) {
        if let result = response.actionResult, !result.success {
            Darwin.exit(1)
        }
    }
}
