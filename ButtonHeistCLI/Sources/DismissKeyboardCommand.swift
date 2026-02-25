import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

struct DismissKeyboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dismiss-keyboard",
        abstract: "Dismiss the keyboard by resigning first responder"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Flag(name: .long, help: "Force-takeover session from another driver")
    var force: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
    var host: String?

    @Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
    var port: UInt16?

    @MainActor
    mutating func run() async throws {
        let connector = DeviceConnector(deviceFilter: device, host: host, port: port, quiet: quiet, force: force)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !quiet { logStatus("Dismissing keyboard...") }
        client.send(.resignFirstResponder)
        let result = try await client.waitForActionResult(timeout: timeout)

        switch format ?? .auto {
        case .json:
            writeOutput(formatActionResultJSON(result))
            if !result.success { Darwin.exit(1) }
        case .human:
            if result.success {
                if !quiet { logStatus("Keyboard dismissed") }
                writeOutput("success")
            } else {
                let msg = result.message ?? "No first responder found"
                if !quiet { logStatus("Failed: \(msg)") }
                writeOutput("failed: \(msg)")
                Darwin.exit(1)
            }
        }
    }
}
