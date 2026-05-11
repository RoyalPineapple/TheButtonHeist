import ArgumentParser
import ButtonHeist
import Foundation

/// Connect (or reconnect) to an iOS device running TheInsideJob.
///
/// With no positional argument, resolves the target via the same precedence
/// the rest of the CLI uses: `--device` flag → `BUTTONHEIST_DEVICE` env var →
/// `.buttonheist.json` config file. With an explicit positional `device`, that
/// host:port is used directly.
struct ConnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Connect to an iOS device running TheInsideJob",
        discussion: """
            With no arguments, reconnects to the currently configured target. \
            Resolution order: --device flag, BUTTONHEIST_DEVICE env var, then \
            the default target in .buttonheist.json (or ~/.config/buttonheist/config.json).

            With an explicit positional device, connects to that host:port directly.

            Examples:
              buttonheist connect                       # Reconnect using configured target
              buttonheist connect 127.0.0.1:1455        # Connect to explicit host:port
              buttonheist connect --device sim --token my-task-slug
            """
    )

    @Argument(help: "Device host:port (omit to use BUTTONHEIST_DEVICE or .buttonheist.json)")
    var device: String?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        // Positional argument takes precedence over the --device flag.
        let resolvedConnection = ConnectionOptions.merging(
            base: connection,
            positionalDevice: device
        )

        // Peek at the resolved environment before invoking TheFence so we can
        // produce a clear error naming what was checked. EnvironmentConfig
        // drops to nil when nothing is configured, and TheFence's own error
        // message is generic.
        let resolved = EnvironmentConfig.resolve(
            deviceFilter: resolvedConnection.device,
            token: resolvedConnection.token,
            autoReconnect: false
        )
        guard resolved.deviceFilter != nil else {
            throw ConnectError.noTargetConfigured
        }

        try await CLIRunner.run(
            connection: resolvedConnection,
            format: output.format,
            request: ["command": TheFence.Command.getInterface.rawValue],
            statusMessage: "Connecting..."
        )
    }
}

// MARK: - Errors

private enum ConnectError: LocalizedError {
    case noTargetConfigured

    var errorDescription: String? {
        switch self {
        case .noTargetConfigured:
            return """
                No connection target configured. Checked:
                  - positional argument
                  - --device flag
                  - BUTTONHEIST_DEVICE env var
                  - .buttonheist.json (current directory)
                  - ~/.config/buttonheist/config.json

                Pass a device (e.g. `buttonheist connect 127.0.0.1:1455`), set \
                BUTTONHEIST_DEVICE, or add a default target to .buttonheist.json.
                """
        }
    }
}

// MARK: - ConnectionOptions Merge

extension ConnectionOptions {
    /// Build a `ConnectionOptions` whose `device` is overridden by a positional
    /// argument when one is present, falling back to the existing `--device` flag.
    static func merging(base: ConnectionOptions, positionalDevice: String?) -> ConnectionOptions {
        var merged = ConnectionOptions()
        merged.device = positionalDevice ?? base.device
        merged.token = base.token
        merged.quiet = base.quiet
        return merged
    }
}
