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
        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !connection.quiet {
            logStatus("Waiting for idle...")
        }

        client.send(.waitForIdle(WaitForIdleTarget(timeout: timeout)))
        let result = try await client.waitForActionResult(timeout: timeout + 5)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Wait for idle")
    }
}
