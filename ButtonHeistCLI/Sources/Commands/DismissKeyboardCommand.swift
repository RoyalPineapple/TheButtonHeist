import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

struct DismissKeyboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dismiss-keyboard",
        abstract: "Dismiss the keyboard by resigning first responder"
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet, force: connection.force)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !connection.quiet { logStatus("Dismissing keyboard...") }
        client.send(.resignFirstResponder)
        let result = try await client.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: format, quiet: connection.quiet, verb: "Keyboard dismiss")
    }
}
