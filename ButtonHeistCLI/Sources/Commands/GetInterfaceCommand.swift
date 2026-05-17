import ArgumentParser
import Foundation
import ButtonHeist

enum CLIGetInterfaceScope: String, ExpressibleByArgument, CaseIterable {
    case visible

    static let allCases: [CLIGetInterfaceScope] = [.visible]
}

struct GetInterfaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.getInterface.rawValue,
        abstract: "Get the current UI element hierarchy from the connected device"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @Option(help: "Diagnostic scope. Omit for app accessibility state; use visible for an on-screen parse")
    var scope: CLIGetInterfaceScope?

    @ButtonHeistActor
    mutating func run() async throws {
        var request: [String: Any] = [
            "command": TheFence.Command.getInterface.rawValue,
            "timeout": timeoutOption.timeout,
        ]
        if let scope { request["scope"] = scope.rawValue }
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: scope == .visible ? "Requesting on-screen interface..." : "Reading interface..."
        )
    }
}
