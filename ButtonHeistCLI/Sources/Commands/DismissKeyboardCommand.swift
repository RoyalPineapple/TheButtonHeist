import ArgumentParser
import ButtonHeist

struct DismissKeyboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dismiss_keyboard",
        abstract: "Dismiss the keyboard by resigning first responder"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !connection.quiet { logStatus("Dismissing keyboard...") }
        client.send(.resignFirstResponder)
        let result = try await client.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Keyboard dismiss")
    }
}
