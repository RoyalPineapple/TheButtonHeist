import ArgumentParser
import ButtonHeist

/// Connect (or reconnect) to an iOS app with Button Heist enabled.
///
/// With no positional argument, resolves the target via the same precedence
/// the rest of the CLI uses: `--device` flag → `BUTTONHEIST_DEVICE` env var →
/// `.buttonheist.json` config file. With an explicit positional `device`, that
/// host:port is used directly.
struct ConnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Connect to an iOS app with Button Heist enabled",
        discussion: """
            With no arguments, establishes the currently configured session. \
            Resolution order: --device flag, BUTTONHEIST_DEVICE env var, then \
            the default target in .buttonheist.json (or ~/.config/buttonheist/config.json).

            With an explicit positional device, connects to that host:port directly. \
            This command returns session state; use get_interface to observe UI hierarchy.

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
            throw ValidationError("""
                No connection target configured. Checked:
                  - positional argument
                  - --device flag
                  - BUTTONHEIST_DEVICE env var
                  - .buttonheist.json (current directory)
                  - ~/.config/buttonheist/config.json

                Pass a device (e.g. `buttonheist connect 127.0.0.1:1455`), set \
                BUTTONHEIST_DEVICE, or add a default target to .buttonheist.json.
                """)
        }

        let fence = TheFence(configuration: resolved.fenceConfiguration)
        fence.onStatus = { message in
            if !resolvedConnection.quiet { logStatus(message) }
        }
        defer { fence.stop() }

        let response = try await fence.execute(request: ["command": TheFence.Command.connect.rawValue])
        CLIRunner.outputResponse(response, format: output.format ?? .auto)
        if response.isFailure {
            throw ExitCode.failure
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
