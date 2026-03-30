import ArgumentParser
import Foundation
import ButtonHeist

struct GetInterfaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get_interface",
        abstract: "Get the current UI element hierarchy from the connected device"
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(help: "Explore the full screen including off-screen content in scroll views")
    var full: Bool = false

    @ButtonHeistActor
    mutating func run() async throws {
        var request: [String: Any] = [
            "command": TheFence.Command.getInterface.rawValue,
            "timeout": timeout,
        ]
        if full { request["full"] = true }
        try await CLIRunner.run(
            connection: connection,
            format: format,
            request: request,
            statusMessage: full ? "Exploring screen..." : "Requesting interface..."
        )
    }
}
