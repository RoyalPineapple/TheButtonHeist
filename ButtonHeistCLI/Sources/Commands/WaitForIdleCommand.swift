import ArgumentParser
import ButtonHeist

struct WaitForIdleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait_for_idle",
        abstract: "Wait for UI animations to settle before reading state or performing actions"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Maximum wait time in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        let config = EnvironmentConfig.resolve(deviceFilter: connection.device, token: connection.token)
        let connector = DeviceConnector(deviceFilter: config.deviceFilter, token: config.token, driverId: config.driverId, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }

        if !connection.quiet {
            logStatus("Waiting for idle...")
        }

        connector.send(.waitForIdle(WaitForIdleTarget(timeout: timeout)))
        let result = try await connector.waitForActionResult(timeout: timeout + 5)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Wait for idle")
    }
}
