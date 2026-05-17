import ArgumentParser
import Foundation
import ButtonHeist

enum CLIGetInterfaceScope: String, ExpressibleByArgument, CaseIterable {
    case full
    case visible

    static let allCases: [CLIGetInterfaceScope] = [.visible]
}

struct GetInterfaceCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.getInterface

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Get the current UI element hierarchy from the connected device"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @Option(help: "Diagnostic scope. Omit for app accessibility state; use visible for an on-screen parse")
    var scope: CLIGetInterfaceScope?

    @Flag(help: .hidden)
    var full: Bool = false

    @ButtonHeistActor
    mutating func run() async throws {
        var request = Self.fenceRequest(["timeout": timeoutOption.timeout])
        if let scope { request["scope"] = scope.rawValue }
        if full { request["full"] = true }
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: scope == .visible ? "Requesting on-screen interface..." : "Reading interface..."
        )
    }
}
