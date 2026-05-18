import ArgumentParser
import Foundation
import ButtonHeist

enum CLIGetInterfaceScope: String, ExpressibleByArgument, CaseIterable {
    case visible

    static let allCases: [CLIGetInterfaceScope] = [.visible]
}

struct GetInterfaceCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.getInterface

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Read the app accessibility hierarchy from the connected device"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @Option(help: "Diagnostic scope. Omit for app accessibility state; use visible for fresh on-screen geometry")
    var scope: CLIGetInterfaceScope?

    @ButtonHeistActor
    mutating func run() async throws {
        var request = Self.fenceRequest()
        if let scope { request[.scope] = scope.rawValue }
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: scope == .visible ? "Requesting visible diagnostic interface..." : "Reading interface..."
        )
    }
}
