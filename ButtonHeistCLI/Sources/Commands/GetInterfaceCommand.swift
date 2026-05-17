import ArgumentParser
import Foundation
import ButtonHeist

enum CLIGetInterfaceScope: String, ExpressibleByArgument, CaseIterable {
    case full
    case visible
}

struct GetInterfaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.getInterface.rawValue,
        abstract: "Get the current UI element hierarchy from the connected device"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @Option(help: "Hierarchy breadth: full (default) or visible")
    var scope: CLIGetInterfaceScope?

    @Flag(help: .hidden)
    var full: Bool = false

    @ButtonHeistActor
    mutating func run() async throws {
        var request: [String: Any] = [
            "command": TheFence.Command.getInterface.rawValue,
            "timeout": timeoutOption.timeout,
        ]
        if let scope { request["scope"] = scope.rawValue }
        if full { request["full"] = true }
        let effectiveScope = scope ?? .full
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: effectiveScope == .full ? "Reading full interface..." : "Requesting visible interface..."
        )
    }
}
